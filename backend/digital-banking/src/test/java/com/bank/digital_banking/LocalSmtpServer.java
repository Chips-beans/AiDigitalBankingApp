package com.bank.digital_banking;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

/** Local-only SMTP capture used by real HTTP integration tests; no external email is sent. */
final class LocalSmtpServer implements AutoCloseable {
    private final ServerSocket server;
    private final ConcurrentMap<String, String> codes = new ConcurrentHashMap<>();
    final AtomicBoolean rejectNext = new AtomicBoolean();

    LocalSmtpServer() throws IOException {
        server = new ServerSocket(0, 50, InetAddress.getLoopbackAddress());
        Thread.startVirtualThread(() -> {
            while (!server.isClosed()) {
                try {
                    Socket socket = server.accept();
                    Thread.startVirtualThread(() -> accept(socket));
                } catch (IOException ex) { if (!server.isClosed()) throw new UncheckedIOException(ex); }
            }
        });
    }
    int port() { return server.getLocalPort(); }
    String code(String email) {
        String result = codes.get(email.toLowerCase(Locale.ROOT));
        if (result == null) throw new AssertionError("No SMTP code captured for " + email);
        return result;
    }
    void reset() { codes.clear(); rejectNext.set(false); }
    private void accept(Socket socket) {
        try (socket;
             var in = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8));
             var out = new PrintWriter(socket.getOutputStream(), true, StandardCharsets.UTF_8)) {
            out.print("220 localhost test SMTP\r\n"); out.flush();
            String recipient = "";
            for (String line; (line = in.readLine()) != null;) {
                String command = line.toUpperCase(Locale.ROOT);
                String reply = "250 OK";
                if (command.startsWith("RCPT TO:")) {
                    recipient = line.substring(line.indexOf('<') + 1, line.indexOf('>')).toLowerCase(Locale.ROOT);
                } else if (command.equals("DATA")) {
                    out.print("354 End with dot\r\n"); out.flush();
                    StringBuilder data = new StringBuilder();
                    for (String body; (body = in.readLine()) != null && !body.equals(".");) data.append(body).append('\n');
                    if (rejectNext.getAndSet(false)) reply = "451 Temporary failure";
                    else {
                        var matcher = Pattern.compile("code is ([0-9]{6})").matcher(data);
                        if (matcher.find()) codes.put(recipient, matcher.group(1));
                    }
                } else if (command.equals("QUIT")) {
                    out.print("221 Bye\r\n"); out.flush(); break;
                }
                out.print(reply + "\r\n"); out.flush();
            }
        } catch (IOException ex) { if (!server.isClosed()) throw new UncheckedIOException(ex); }
    }
    @Override public void close() throws IOException { server.close(); }
}
