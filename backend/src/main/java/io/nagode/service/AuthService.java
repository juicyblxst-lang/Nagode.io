package io.nagode.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;

@Service
public class AuthService {
  private final JdbcTemplate db; private final BCryptPasswordEncoder encoder=new BCryptPasswordEncoder(12);
  public AuthService(JdbcTemplate db){this.db=db;}
  public record User(UUID id,String email,String displayName){}
  public record Session(UUID id,UUID userId,String token){ }
  @Transactional
  public User register(String email,String password,String displayName){
    if(password==null||password.length()<10)throw new IllegalArgumentException("password must contain at least 10 characters");
    String e=email.trim().toLowerCase(Locale.ROOT);if(e.isBlank())throw new IllegalArgumentException("email is required");
    UUID id=UUID.randomUUID();db.update("insert into users(id,email,password_hash,display_name) values(?,?,?,?)",id,e,encoder.encode(password),displayName.trim());
    UUID account=UUID.randomUUID();db.update("insert into accounts(id,owner_type,owner_id,type,currency) values(?,?,?,?,?)",account,"USER",id.toString(),"USER_WALLET","NGN");db.update("insert into account_balances(account_id,balance) values(?,0)",account);return new User(id,e,displayName.trim());
  }
  @Transactional
  public Session login(String email,String password){
    String e=email.trim().toLowerCase(Locale.ROOT);var rows=db.query("select id,password_hash,display_name from users where email=?",(r,n)->new Object[]{UUID.fromString(r.getString(1)),r.getString(2),r.getString(3)},e);if(rows.isEmpty()||!encoder.matches(password,(String)rows.getFirst()[1]))throw new IllegalArgumentException("invalid credentials");UUID uid=(UUID)rows.getFirst()[0];String raw=random();String hash=hash(raw);UUID sid=UUID.randomUUID();db.update("insert into sessions(id,user_id,token_hash,expires_at) values(?,?,?,?)",sid,uid,hash,Instant.now().plus(Duration.ofDays(7)));return new Session(sid,uid,raw);}
  @Transactional public void logout(String token){if(token!=null)db.update("delete from sessions where token_hash=?",hash(token));}
  public User current(String token){if(token==null||token.isBlank())return null;var rows=db.query("select u.id,u.email,u.display_name from sessions s join users u on u.id=s.user_id where s.token_hash=? and s.expires_at>now()",(r,n)->new User(UUID.fromString(r.getString(1)),r.getString(2),r.getString(3)),hash(token));return rows.isEmpty()?null:rows.getFirst();}
  public UUID walletFor(UUID user){return db.queryForObject("select id from accounts where owner_type='USER' and owner_id=? and type='USER_WALLET' and currency='NGN'",UUID.class,user.toString());}
  private String random(){byte[] b=new byte[32];new SecureRandom().nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
  private String hash(String s){try{return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
}
