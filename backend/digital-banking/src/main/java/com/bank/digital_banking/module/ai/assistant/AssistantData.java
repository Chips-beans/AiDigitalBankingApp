package com.bank.digital_banking.module.ai.assistant;

import com.bank.digital_banking.module.auth.entity.User;
import com.bank.digital_banking.module.account.service.AccountService;
import com.bank.digital_banking.module.analytics.service.AnalyticsService;
import com.bank.digital_banking.module.transaction.service.TransactionService;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import lombok.RequiredArgsConstructor;
import java.math.*;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantModels.*;
import static com.bank.digital_banking.module.ai.assistant.AssistantSupport.*;

/** Read-only, owner-scoped financial tools. No model text is executed as SQL. */
@Service @RequiredArgsConstructor @Transactional(readOnly=true,isolation=org.springframework.transaction.annotation.Isolation.REPEATABLE_READ)
public class AssistantData {
    private final NamedParameterJdbcTemplate jdbc;
    private final AccountService accounts;
    private final TransactionService transactions;
    private final AnalyticsService analytics;
    private final AssistantKnowledge knowledge;
    private final Clock clock;

    public Filters validate(Filters f) {
        if(f==null) return Filters.empty();
        if(f.currency()!=null && !Set.of("USD","KHR").contains(f.currency())) throw invalid();
        if(f.accountNumber()!=null && !f.accountNumber().matches("[0-9]{10,20}")) throw invalid();
        if(f.reference()!=null && !f.reference().matches("[A-Za-z0-9_-]{1,36}")) throw invalid();
        if(f.direction()!=null && !Set.of("IN","OUT").contains(f.direction())) throw invalid();
        if(f.type()!=null && !Set.of("TRANSFER","DEPOSIT","WITHDRAWAL").contains(f.type())) throw invalid();
        if(f.status()!=null && !Set.of("PENDING","SUCCESS","FAILED","REVERSED").contains(f.status())) throw invalid();
        try {
            if(f.month()!=null) month(f.month());
            if(f.from()!=null) LocalDate.parse(f.from());
            if(f.to()!=null) LocalDate.parse(f.to());
            if(f.amount()!=null) {
                if(!f.amount().matches("[0-9]{1,13}(?:\\.[0-9]{1,2})?")) throw invalid();
                var amount=new BigDecimal(f.amount());
                if(amount.signum()<=0 || ("KHR".equals(f.currency()) && amount.stripTrailingZeros().scale()>0)) throw invalid();
            }
        } catch(DateTimeException|NumberFormatException ex) { throw invalid(); }
        return f;
    }
    public YearMonth month(String value) {
        if(value==null) return YearMonth.now(clock.withZone(ZONE));
        if(!value.matches("[0-9]{4}-[0-9]{2}")) throw invalid();
        var result=YearMonth.parse(value);
        if(result.getYear()<2000 || result.getYear()>2100) throw invalid();
        return result;
    }
    public void validateSelected(User user,Filters context) {
        validate(context);
        if(context!=null && context.accountNumber()!=null) accounts.getAccountByNumber(user,context.accountNumber());
    }
    public Grounded answer(User user,Intent intent,String locale) {
        var f=validate(intent.filters());
        var cards=new ArrayList<Card>(); var facts=new LinkedHashMap<String,String>();
        String reply;
        switch(intent.capability()) {
            case BALANCES -> {
                if(f.accountNumber()!=null) accounts.getAccountByNumber(user,f.accountNumber());
                for(String currency:currencies(f)) {
                    var p=new HashMap<String,Object>(); p.put("user",user.getId()); p.put("currency",currency);
                    String filter=f.accountNumber()==null?"":" AND account_number=:account";
                    p.put("account",f.accountNumber());
                    var totals=jdbc.queryForMap("SELECT COALESCE(sum(balance),0) total,count(*) count FROM accounts WHERE user_id=:user AND currency=:currency"+filter,p);
                    var fields=new ArrayList<Field>();
                    String total=money((BigDecimal)totals.get("total"),currency);
                    fields.add(new Field(t(locale,"Total balance","សមតុល្យសរុប"),total));
                    fields.add(new Field(t(locale,"Accounts","គណនី"),totals.get("count").toString()));
                    facts.put(currency+"_balance",total);
                    var actions=new ArrayList<Action>();
                    jdbc.query("SELECT account_number,balance,status FROM accounts WHERE user_id=:user AND currency=:currency"+filter+" ORDER BY id LIMIT 10",p,(rs,row)-> {
                        String number=rs.getString("account_number");
                        fields.add(new Field("•••• "+number.substring(number.length()-4),money(rs.getBigDecimal("balance"),currency)+" · "+rs.getString("status")));
                        actions.add(action("ACCOUNT",number,number,currency,null)); return number;
                    });
                    actions.add(action("ACCOUNTS",null,null,null,null));
                    cards.add(new Card("BALANCE",currency,fields,actions));
                }
                reply=t(locale,"Here are your verified account balances.","នេះជាសមតុល្យគណនីដែលបានផ្ទៀងផ្ទាត់របស់អ្នក។");
            }
            case MONTHLY -> {
                var m=month(f.month());
                f=new Filters(f.currency(),null,m.toString(),null,null,null,null,null,null,null);
                // A summary is customer-wide, matching Monthly Analytics (not a selected-wallet subtotal).
                for(String currency:currencies(f)) {
                    var overview=analytics.getMonthlyOverview(user,m.getYear(),m.getMonthValue(),currency);
                    var params=Map.<String,Object>of("user",user.getId(),"currency",currency,
                            "start",m.atDay(1).atStartOfDay(ZONE).toOffsetDateTime(),"end",m.plusMonths(1).atDay(1).atStartOfDay(ZONE).toOffsetDateTime());
                    var credits=jdbc.queryForObject("SELECT COALESCE(sum(t.amount),0) FROM transactions t JOIN accounts a ON a.id=t.destination_account_id WHERE a.user_id=:user AND t.currency=:currency AND t.status='SUCCESS' AND t.operation='TEST_OPENING_CREDIT' AND t.created_at>=:start AND t.created_at<:end",params,BigDecimal.class);
                    String income=currency+" "+overview.totalIncome(), expense=currency+" "+overview.totalExpense();
                    facts.put(currency+"_income",income); facts.put(currency+"_outgoing",expense);
                    facts.put(currency+"_test_credit",money(credits,currency)); facts.put("period",m.toString());
                    cards.add(new Card("MONTHLY",currency+" · "+m,List.of(
                            new Field(t(locale,"Income","ប្រាក់ចូល"),income),
                            new Field(t(locale,"Outgoing","ប្រាក់ចេញ"),expense),
                            new Field(t(locale,"Included test opening credits","រួមបញ្ចូលប្រាក់សាកល្បងពេលបើកគណនី"),money(credits,currency)),
                            new Field(t(locale,"Time zone","តំបន់ពេលវេលា"),ZONE.toString())),
                            List.of(action("ANALYTICS",null,null,currency,m.toString()))));
                }
                reply=t(locale,"Monthly cash flow excludes transfers between your own accounts. Test opening credits are labelled separately.","លំហូរសាច់ប្រាក់ប្រចាំខែមិនរាប់ការផ្ទេររវាងគណនីផ្ទាល់ខ្លួនទេ។ ប្រាក់សាកល្បងត្រូវបានបញ្ជាក់ដាច់ដោយឡែក។");
            }
            case SEARCH -> {
                if(f.amount()!=null && f.currency()==null) return clarification(locale,f);
                var page=search(user,f,null,20);
                cards.addAll(postingCards(page.items(),locale));
                if(page.nextCursor()!=null) cards.add(new Card("MORE",t(locale,"More transactions","ប្រតិបត្តិការបន្ថែម"),List.of(),
                        List.of(new Action("MORE",null,null,null,null,page.filters(),page.nextCursor()))));
                reply=page.items().isEmpty()?t(locale,"No transactions match these filters.","មិនមានប្រតិបត្តិការដែលត្រូវនឹងលក្ខខណ្ឌនេះទេ។"):
                        t(locale,"These transactions match your search. Open a receipt for its recorded details.","ប្រតិបត្តិការទាំងនេះត្រូវនឹងការស្វែងរករបស់អ្នក។ បើកបង្កាន់ដៃដើម្បីមើលព័ត៌មាន។");
                facts.put("matches_on_page",Integer.toString(page.items().size()));
                f=page.filters();
            }
            case DETAIL -> {
                if(f.reference()==null) return new Grounded(new Answer(t(locale,"Which transaction reference should I check?","តើអ្នកចង់ពិនិត្យលេខយោងប្រតិបត្តិការណា?"),List.of(),now(clock),"NOT_NEEDED"),facts,f);
                var tx=transactions.getTransactionByReference(user,f.reference());
                var p=postingByReference(user,tx.getReferenceNumber());
                cards.addAll(postingCards(List.of(p),locale));
                facts.put("transaction_amount",p.currency()+" "+p.amount()); facts.put("transaction_status",p.status());
                reply=t(locale,"This is the recorded transaction status. It does not establish external-bank settlement.","នេះជាស្ថានភាពប្រតិបត្តិការដែលបានកត់ត្រា។ វាមិនបញ្ជាក់ការទូទាត់ជាមួយធនាគារខាងក្រៅទេ។");
            }
            case HELP -> { return knowledge.answer(intent.topic(),locale,now(clock)); }
            case CLARIFY -> { return clarification(locale,f); }
            default -> { reply=t(locale,"I can help with Kesor balances, transactions, monthly cash flow and app instructions. Category budgets and payment execution are not available here.","ខ្ញុំអាចជួយអំពីសមតុល្យ ប្រតិបត្តិការ លំហូរប្រាក់ប្រចាំខែ និងការប្រើកម្មវិធី Kesor។ មុខងារថវិកាតាមប្រភេទ និងការផ្ញើប្រាក់មិនមាននៅទីនេះទេ។"); }
        }
        return new Grounded(new Answer(reply,List.copyOf(cards),now(clock),"NOT_NEEDED"),facts,f);
    }
    private Grounded clarification(String locale,Filters f) {
        return new Grounded(new Answer(t(locale,"Please specify the currency (USD or KHR), account, period or transaction reference needed for this question.","សូមបញ្ជាក់រូបិយប័ណ្ណ (USD ឬ KHR) គណនី រយៈពេល ឬលេខយោងប្រតិបត្តិការសម្រាប់សំណួរនេះ។"),List.of(),now(clock),"NOT_NEEDED"),Map.of(),f);
    }
    private List<String> currencies(Filters f) { return f.currency()==null?List.of("USD","KHR"):List.of(f.currency()); }
    public static String money(BigDecimal value,String currency) { return currency+" "+value.setScale("USD".equals(currency)?2:0,RoundingMode.UNNECESSARY).toPlainString(); }
    public static Action action(String type,String value,String account,String currency,String month) { return new Action(type,value,account,currency,month,null,null); }

    private static final String SELECT="SELECT t.*,s.account_number src,d.account_number dst,CASE WHEN s.user_id=:user THEN s.account_number ELSE d.account_number END owned,CASE WHEN s.user_id=:user AND d.user_id=:user THEN 'OWN' WHEN s.user_id=:user THEN 'OUT' ELSE 'IN' END direction FROM transactions t LEFT JOIN accounts s ON s.id=t.source_account_id LEFT JOIN accounts d ON d.id=t.destination_account_id WHERE (s.user_id=:user OR d.user_id=:user)";
    public SearchPage search(User user,Filters input,String cursor,int limit) {
        var f=validate(input); size(limit);
        if(f.amount()!=null && f.currency()==null) throw invalid();
        var m=month(f.month());
        LocalDate from=f.from()==null?m.atDay(1):LocalDate.parse(f.from());
        LocalDate to=f.to()==null?m.atEndOfMonth():LocalDate.parse(f.to());
        if(to.isBefore(from)||ChronoUnit.DAYS.between(from,to)+1>366) throw invalid();
        var normalized=new Filters(f.currency(),f.accountNumber(),m.toString(),from.toString(),to.toString(),f.amount(),f.direction(),f.type(),f.status(),f.reference());
        var p=new HashMap<String,Object>(); p.put("user",user.getId());
        p.put("from",from.atStartOfDay(ZONE).toOffsetDateTime()); p.put("to",to.plusDays(1).atStartOfDay(ZONE).toOffsetDateTime());
        var sql=new StringBuilder(SELECT).append(" AND t.created_at>=:from AND t.created_at<:to");
        if(f.currency()!=null) { sql.append(" AND t.currency=:currency"); p.put("currency",f.currency()); }
        if(f.amount()!=null) { sql.append(" AND t.amount=:amount"); p.put("amount",new BigDecimal(f.amount())); }
        if(f.accountNumber()!=null) { sql.append(" AND (s.account_number=:account OR d.account_number=:account)"); p.put("account",f.accountNumber()); }
        if(f.direction()!=null) sql.append(" AND ").append(f.direction().equals("OUT")?"s.user_id=:user":"d.user_id=:user");
        for(var pair:List.of(new String[]{"type",f.type(),"transaction_type"},new String[]{"status",f.status(),"status"},new String[]{"reference",f.reference(),"reference_number"})) {
            if(pair[1]!=null) { sql.append(" AND t.").append(pair[2]).append("=:").append(pair[0]); p.put(pair[0],pair[1]); }
        }
        var boundary=boundary(cursor);
        if(boundary!=null) {
            long id; try { id=Long.parseLong(boundary.id()); } catch(NumberFormatException ex) { throw invalid(); }
            sql.append(" AND (t.created_at<:before OR (t.created_at=:before AND t.id<:id))"); p.put("before",boundary.time());p.put("id",id);
        }
        sql.append(" ORDER BY t.created_at DESC,t.id DESC LIMIT :limit");p.put("limit",limit+1);
        var rows=jdbc.query(sql.toString(),p,(rs,row)->mapPosting(rs));
        String next=null;
        if(rows.size()>limit) { rows=new ArrayList<>(rows.subList(0,limit)); var last=rows.getLast(); next=cursor(last.createdAt(),Long.toString(last.id())); }
        return new SearchPage(rows,next,normalized);
    }
    private Posting postingByReference(User user,String reference) {
        return jdbc.query(SELECT+" AND t.reference_number=:reference",Map.of("user",user.getId(),"reference",reference),(rs,row)->mapPosting(rs)).stream().findFirst().orElseThrow(AssistantSupport::missing);
    }
    private Posting mapPosting(java.sql.ResultSet rs) throws java.sql.SQLException {
        String currency=rs.getString("currency");
        return new Posting(rs.getLong("id"),rs.getString("reference_number"),rs.getString("src"),rs.getString("dst"),rs.getString("owned"),
                rs.getBigDecimal("amount").setScale(currency.equals("USD")?2:0,RoundingMode.UNNECESSARY).toPlainString(),
                rs.getBigDecimal("fee").setScale(currency.equals("USD")?2:0,RoundingMode.UNNECESSARY).toPlainString(),currency,
                rs.getString("transaction_type"),rs.getString("status"),rs.getString("direction"),"TEST_OPENING_CREDIT".equals(rs.getString("operation")),rs.getObject("created_at",OffsetDateTime.class));
    }
    public List<Card> postingCards(List<Posting> rows,String locale) {
        return rows.stream().map(p -> new Card("TRANSACTION",p.testFunding()?t(locale,"Test opening credit","ប្រាក់សាកល្បងពេលបើកគណនី"):p.type(),List.of(
                new Field(t(locale,"Amount","ចំនួនប្រាក់"),p.currency()+" "+p.amount()),new Field(t(locale,"Status","ស្ថានភាព"),p.status()),
                new Field(t(locale,"Reference","លេខយោង"),p.reference()),new Field(t(locale,"Date","កាលបរិច្ឆេទ"),p.createdAt().atZoneSameInstant(ZONE).toString())),
                List.of(action("TRANSACTION",p.reference(),p.ownedAccount(),p.currency(),null)))).toList();
    }
}
