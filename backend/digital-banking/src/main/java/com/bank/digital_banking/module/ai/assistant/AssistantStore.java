package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.module.ai.adapter.AIProperties;
import com.bank.digital_banking.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import tools.jackson.databind.ObjectMapper;
import jakarta.annotation.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.concurrent.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantSupport.*;

/** Short database transactions only. No connection/row lock survives a provider call. */
@Service
public class AssistantStore {
    private final JdbcTemplate jdbc;
    private final ObjectMapper json;
    private final Clock clock;
    private final AIProperties properties;
    private final TransactionTemplate tx;
    private final ScheduledExecutorService maintenance=Executors.newSingleThreadScheduledExecutor(r -> Thread.ofPlatform().daemon().name("assistant-maintenance").unstarted(r));
    private LocalDate lastPurge;
    public AssistantStore(JdbcTemplate jdbc,ObjectMapper json,Clock clock,AIProperties properties,PlatformTransactionManager manager) {
        this.jdbc=jdbc;this.json=json;this.clock=clock;this.properties=properties;
        tx=new TransactionTemplate(manager); tx.setPropagationBehavior(org.springframework.transaction.TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }
    @PostConstruct void start() { maintenance.scheduleWithFixedDelay(() -> {
        try { interruptStale(); var day=LocalDate.now(clock.withZone(ZONE)); if(!day.equals(lastPurge)) { purge(); lastPurge=day; } }
        catch(RuntimeException ex) { org.slf4j.LoggerFactory.getLogger(getClass()).warn("Assistant maintenance unavailable: {}",ex.getClass().getSimpleName()); }
    },60,60,TimeUnit.SECONDS); }
    @PreDestroy void stop() { maintenance.shutdownNow(); }
    private void lockUser(long user) { jdbc.queryForObject("SELECT id FROM users WHERE id=? FOR UPDATE",Long.class,user); }
    public Conversation owned(long user,UUID id) {
        var time=now(clock);
        return jdbc.query("""
            SELECT * FROM ai_conversations c WHERE c.user_id=? AND c.id=? AND
            (c.updated_at>? OR EXISTS(SELECT 1 FROM ai_messages m WHERE m.conversation_id=c.id AND m.expires_at>?)
             OR EXISTS(SELECT 1 FROM ai_requests r WHERE r.conversation_id=c.id AND r.status='PENDING' AND r.expires_at>?))
            """,(rs,n)->conversation(rs),user,id,time.minusDays(30),time,time).stream().findFirst().orElseThrow(AssistantSupport::missing);
    }
    private Conversation conversation(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Conversation(rs.getObject("id",UUID.class),rs.getString("title"),rs.getObject("created_at",OffsetDateTime.class),rs.getObject("updated_at",OffsetDateTime.class));
    }
    public Page<Conversation> conversations(long user,String cursor,int limit) {
        size(limit); var b=boundary(cursor); var args=new ArrayList<Object>();args.add(user);args.add(now(clock).minusDays(30));
        String condition="";
        if(b!=null) {
            UUID id;try { id=UUID.fromString(b.id()); } catch(IllegalArgumentException ex) { throw invalid(); }
            condition=" AND (updated_at<? OR (updated_at=? AND id<?))"; args.add(b.time());args.add(b.time());args.add(id);
        }
        args.add(limit+1);
        var rows=jdbc.query("SELECT * FROM ai_conversations WHERE user_id=? AND updated_at>?"+condition+" ORDER BY updated_at DESC,id DESC LIMIT ?",(rs,n)->conversation(rs),args.toArray());
        String next=null;
        if(rows.size()>limit) { rows=new ArrayList<>(rows.subList(0,limit)); var last=rows.getLast(); next=cursor(last.updatedAt(),last.id().toString()); }
        return new Page<>(rows,next);
    }
    public Conversation create(long user,String requestKey) {
        key(requestKey);
        return tx.execute(status -> {
            lockUser(user);
            var existing=request(user,requestKey);
            if(existing!=null) {
                if(!"CREATE".equals(existing.get("kind"))) throw conflict();
                if(existing.get("conversation_id")==null) throw missing();
                return owned(user,(UUID)existing.get("conversation_id"));
            }
            var time=now(clock);var id=UUID.randomUUID();
            jdbc.update("INSERT INTO ai_conversations(id,user_id,title,created_at,updated_at) VALUES(?,?,'New conversation',?,?)",id,user,time,time);
            jdbc.update("INSERT INTO ai_requests(id,user_id,conversation_id,request_key,kind,fingerprint,status,created_at,expires_at) VALUES(?,?,?,?,'CREATE',?,'COMPLETED',?,?)",UUID.randomUUID(),user,id,requestKey,hash("CREATE:v1"),time,time.plusDays(30));
            return owned(user,id);
        });
    }
    public Conversation recoverCreation(long user,String requestKey) {
        key(requestKey);var row=request(user,requestKey);
        if(row==null || !"CREATE".equals(row.get("kind")) || row.get("conversation_id")==null) throw missing();
        return owned(user,(UUID)row.get("conversation_id"));
    }
    public Conversation rename(long user,UUID id,String title) {
        if(title==null || title.isBlank() || title.length()>80) throw invalid();
        AssistantPrivacy.rejectSecrets(title);
        return tx.execute(status -> {
            lockUser(user);owned(user,id);
            jdbc.update("UPDATE ai_conversations SET title=? WHERE user_id=? AND id=?",title.trim(),user,id);
            return owned(user,id);
        });
    }
    public void delete(long user,UUID id) {
        tx.executeWithoutResult(status -> {
            lockUser(user);owned(user,id);
            // Preserve a create-key tombstone so an old lost-response retry cannot recreate a deleted chat.
            jdbc.update("UPDATE ai_requests SET conversation_id=NULL,status='FAILED',result_json=NULL WHERE user_id=? AND conversation_id=? AND kind='CREATE'",user,id);
            jdbc.update("DELETE FROM ai_conversations WHERE user_id=? AND id=?",user,id);
        });
    }
    public Page<Message> messages(long user,UUID conversation,String cursor,int limit) {
        owned(user,conversation);size(limit);var b=boundary(cursor);var args=new ArrayList<Object>();args.add(conversation);args.add(now(clock));
        String condition="";
        if(b!=null) {
            long id;try { id=Long.parseLong(b.id()); } catch(NumberFormatException ex) { throw invalid(); }
            condition=" AND (created_at<? OR (created_at=? AND id<?))";args.add(b.time());args.add(b.time());args.add(id);
        }
        args.add(limit+1);
        var rows=jdbc.query("SELECT * FROM ai_messages WHERE conversation_id=? AND expires_at>?"+condition+" ORDER BY created_at DESC,id DESC LIMIT ?",(rs,n)->new Message(rs.getLong("id"),rs.getString("message"),rs.getString("locale"),decode(json,rs.getString("answer_json"),Answer.class),rs.getObject("created_at",OffsetDateTime.class)),args.toArray());
        String next=null;
        if(rows.size()>limit) { rows=new ArrayList<>(rows.subList(0,limit)); var last=rows.getLast();next=cursor(last.createdAt(),Long.toString(last.id())); }
        return new Page<>(rows,next);
    }
    public Filters lastFilters(long user,UUID conversation) {
        owned(user,conversation);
        return jdbc.query("SELECT filters_json FROM ai_messages WHERE conversation_id=? AND expires_at>? ORDER BY created_at DESC,id DESC LIMIT 1",(rs,n)->decode(json,rs.getString(1),Filters.class),conversation,now(clock)).stream().findFirst().orElse(Filters.empty());
    }
    private Map<String,Object> request(long user,String key) {
        return jdbc.queryForList("SELECT * FROM ai_requests WHERE user_id=? AND request_key=? AND expires_at>?",user,key,now(clock)).stream().findFirst().orElse(null);
    }
    private Turn turn(Map<String,Object> row) {
        UUID id=(UUID)row.get("id");
        var value=(String)row.get("result_json");
        if(value!=null) return decode(json,value,Turn.class);
        return new Turn(id,"PENDING",null,null);
    }
    public Turn status(long user,UUID conversation,String key) {
        owned(user,conversation);AssistantSupport.key(key);
        var row=request(user,key);
        if(row==null || !conversation.equals(row.get("conversation_id")) || !"MESSAGE".equals(row.get("kind"))) throw missing();
        var result=turn(row);
        var created=((java.sql.Timestamp)row.get("created_at")).toInstant();
        if("PENDING".equals(result.status()) && !created.plusSeconds(120).isAfter(clock.instant())) return new Turn(result.requestId(),"FAILED",null,"AI_REQUEST_INTERRUPTED");
        return result;
    }
    public record Claim(boolean acquired,Turn turn) {}
    public Claim claim(long user,UUID conversation,String key,String fingerprint) {
        AssistantSupport.key(key);
        return tx.execute(status -> {
            lockUser(user);owned(user,conversation);
            interruptStale(user);
            var existing=request(user,key);
            if(existing!=null) {
                if(!"MESSAGE".equals(existing.get("kind")) || !conversation.equals(existing.get("conversation_id")) || !fingerprint.equals(existing.get("fingerprint"))) throw conflict();
                return new Claim(false,turn(existing));
            }
            interruptStale(user);
            int pending=jdbc.queryForObject("SELECT count(*) FROM ai_requests WHERE user_id=? AND conversation_id=? AND status='PENDING'",Integer.class,user,conversation);
            if(pending>0) throw new ApiException(HttpStatus.CONFLICT,"AI_REQUEST_IN_PROGRESS","Check the pending question before sending another.");
            chargeLocked(user);
            var time=now(clock);var id=UUID.randomUUID();
            jdbc.update("INSERT INTO ai_requests(id,user_id,conversation_id,request_key,kind,fingerprint,status,created_at,expires_at) VALUES(?,?,?,?,'MESSAGE',?,'PENDING',?,?)",id,user,conversation,key,fingerprint,time,time.plusDays(30));
            return new Claim(true,new Turn(id,"PENDING",null,null));
        });
    }
    public void charge(long user) { tx.executeWithoutResult(status -> {lockUser(user);chargeLocked(user);}); }
    private void chargeLocked(long user) {
        var time=now(clock); var day=time.atZoneSameInstant(ZONE).toLocalDate();
        String minute="M:"+time.toEpochSecond()/60, daily="D:"+day;
        var windows=List.of(minute,daily);
        for(String window:windows) jdbc.update("INSERT INTO ai_usage_limits(user_id,window_key,requests,expires_at) VALUES(?,?,0,?) ON CONFLICT DO NOTHING",user,window,window.equals(minute)?time.plusMinutes(2):day.plusDays(1).atStartOfDay(ZONE).toOffsetDateTime());
        int usedMinute=jdbc.queryForObject("SELECT requests FROM ai_usage_limits WHERE user_id=? AND window_key=?",Integer.class,user,minute);
        int usedDay=jdbc.queryForObject("SELECT requests FROM ai_usage_limits WHERE user_id=? AND window_key=?",Integer.class,user,daily);
        if(usedMinute>=Math.max(1,properties.getMinuteLimit()) || usedDay>=Math.max(1,properties.getDailyLimit())) {
            long retry=usedDay>=Math.max(1,properties.getDailyLimit())?Math.max(1,Duration.between(time,day.plusDays(1).atStartOfDay(ZONE).toOffsetDateTime()).toSeconds()):60-time.toEpochSecond()%60;
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS,"AI_RATE_LIMITED","Assistant request limit reached. Try again later.",retry);
        }
        for(String window:windows) jdbc.update("UPDATE ai_usage_limits SET requests=requests+1 WHERE user_id=? AND window_key=?",user,window);
    }
    public Turn finish(long user,UUID conversation,String key,Question question,Grounded grounded,String failure) {
        return tx.execute(status -> {
            lockUser(user);owned(user,conversation);
            interruptStale(user);
            var row=request(user,key);if(row==null || !conversation.equals(row.get("conversation_id"))) throw missing();
            var previous=turn(row);if(!"PENDING".equals(previous.status())) return previous;
            var result=new Turn(previous.requestId(),failure==null?"COMPLETED":"FAILED",grounded==null?null:grounded.answer(),failure);
            jdbc.update("UPDATE ai_requests SET status=?,result_json=? WHERE id=? AND status='PENDING'",result.status(),encode(json,result),result.requestId());
            if(failure==null) {
                var time=now(clock);
                jdbc.update("INSERT INTO ai_messages(conversation_id,request_id,message,locale,answer_json,filters_json,created_at,expires_at) VALUES(?,?,?,?,?,?,?,?)",conversation,result.requestId(),question.message(),question.locale(),encode(json,grounded.answer()),encode(json,grounded.filters()),time,((java.sql.Timestamp)row.get("expires_at")).toInstant().atOffset(ZoneOffset.UTC));
                jdbc.update("UPDATE ai_conversations SET updated_at=? WHERE user_id=? AND id=?",time,user,conversation);
            }
            return result;
        });
    }
    private ApiException conflict() { return new ApiException(HttpStatus.CONFLICT,"AI_IDEMPOTENCY_CONFLICT","This request key belongs to a different assistant request."); }
    public void interruptStale() {
        jdbc.query("SELECT DISTINCT user_id FROM ai_requests WHERE status='PENDING' AND created_at<=?",(rs,n)->rs.getLong(1),now(clock).minusMinutes(2)).forEach(user -> tx.executeWithoutResult(status -> {lockUser(user);interruptStale(user);}));
    }
    private void interruptStale(long user) {
        jdbc.query("SELECT id FROM ai_requests WHERE user_id=? AND status='PENDING' AND created_at<=?",(rs,n)->rs.getObject(1,UUID.class),user,now(clock).minusMinutes(2)).forEach(id -> jdbc.update("UPDATE ai_requests SET status='FAILED',result_json=? WHERE id=? AND status='PENDING'",encode(json,new Turn(id,"FAILED",null,"AI_REQUEST_INTERRUPTED")),id));
    }
    public void purge() {
        tx.executeWithoutResult(status -> {
            var time=now(clock);
            jdbc.update("DELETE FROM ai_requests WHERE expires_at<=?",time);
            jdbc.update("DELETE FROM ai_messages WHERE expires_at<=?",time);
            jdbc.update("DELETE FROM ai_conversations c WHERE updated_at<=? AND NOT EXISTS(SELECT 1 FROM ai_messages m WHERE m.conversation_id=c.id) AND NOT EXISTS(SELECT 1 FROM ai_requests r WHERE r.conversation_id=c.id AND r.status='PENDING')",time.minusDays(30));
            jdbc.update("DELETE FROM ai_usage_limits WHERE expires_at<=?",time);
        });
    }
}
