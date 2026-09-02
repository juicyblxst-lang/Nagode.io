package io.nagode.service;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.TimeUnit;

@Service
public class IdempotencyService {
  public record Begin(boolean replay, boolean conflict, boolean inProgress, int code, String body, UUID resourceId) {}
  private final JdbcTemplate db; private final StringRedisTemplate redis; private final long ttl;
  public IdempotencyService(JdbcTemplate db,StringRedisTemplate redis,org.springframework.core.env.Environment env){this.db=db;this.redis=redis;this.ttl=Long.parseLong(env.getProperty("nagode.idempotency-ttl-seconds","86400"));}
  public Begin begin(String merchant,String key,String canonicalRequest){
    if(key==null||key.isBlank()||key.length()>255)throw new IllegalArgumentException("Idempotency-Key is required");
    String hash=hash(canonicalRequest); String lock="nagode:idem:"+merchant+":"+key; boolean locked=false;
    try { locked=Boolean.TRUE.equals(redis.opsForValue().setIfAbsent(lock,"1",ttl,TimeUnit.SECONDS)); } catch(Exception ignored) {}
    try {
      var rows=db.query("select request_hash,status,response_code,response_body,resource_id from idempotency_keys where merchant_id=? and idem_key=?",(r,n)->new Object[]{r.getString(1),r.getString(2),r.getObject(3),r.getString(4),r.getObject(5)},merchant,key);
      if(!rows.isEmpty()) {var x=rows.getFirst();String old=(String)x[0];if(!old.equals(hash))return new Begin(false,true,false,422,"{\"error\":\"IDEMPOTENCY_KEY_REUSE\",\"message\":\"request body differs from the original\"}",null);if("COMPLETED".equals(x[1]))return new Begin(true,false,false,(Integer)x[2],(String)x[3],x[4]==null?null:UUID.fromString(x[4].toString()));return new Begin(false,false,true,409,"{\"error\":\"REQUEST_IN_PROGRESS\",\"message\":\"an identical request is already being processed\"}",null);}
      try {db.update("insert into idempotency_keys(merchant_id,idem_key,request_hash,status) values(?,?,?,'IN_PROGRESS')",merchant,key,hash);}catch(DuplicateKeyException e){return begin(merchant,key,canonicalRequest);}
      return new Begin(false,false,false,0,null,null);
    } finally {if(locked)try{redis.delete(lock);}catch(Exception ignored){}}
  }
  @Transactional(propagation=Propagation.REQUIRES_NEW)
  public void complete(String merchant,String key,UUID resource,int code,String body){db.update("update idempotency_keys set status='COMPLETED',resource_id=?,response_code=?,response_body=?::jsonb where merchant_id=? and idem_key=?",resource,code,body,merchant,key);}
  @Transactional(propagation=Propagation.REQUIRES_NEW)
  public void fail(String merchant,String key,int code,String body){db.update("update idempotency_keys set status='COMPLETED',response_code=?,response_body=?::jsonb where merchant_id=? and idem_key=?",code,body,merchant,key);}
  private String hash(String s){try{byte[] b=MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));return HexFormat.of().formatHex(b);}catch(Exception e){throw new IllegalStateException(e);}}
}
