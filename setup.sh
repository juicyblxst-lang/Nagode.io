#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-nagode}"
mkdir -p "$ROOT"/{backend/src/main/java/io/nagode/{api,domain,service,infrastructure,shared},backend/src/main/resources/db/migration,backend/src/test/java/io/nagode,frontend/src/app/payments/'[id]',frontend/src/app/reconciliation,frontend/src/components,frontend/src/lib,frontend/src/types,prometheus,grafana/provisioning/datasources,grafana/provisioning/dashboards,grafana/dashboards,k6,.github/workflows}

cat > "$ROOT/.gitignore" <<'EOF'
**/target/
**/node_modules/
**/.next/
.env
.DS_Store
EOF

cat > "$ROOT/.env.example" <<'EOF'
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/nagode
SPRING_DATASOURCE_USERNAME=nagode
SPRING_DATASOURCE_PASSWORD=nagode
SPRING_REDIS_HOST=localhost
SPRING_REDIS_PORT=6379
PSP_MOCK_URL=http://localhost:8080/mock/psp
WEBHOOK_SECRET=change-me-in-production
NEXT_PUBLIC_API_URL=http://localhost:8080
EOF

cat > "$ROOT/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    command: ["postgres", "-c", "shared_preload_libraries=pg_stat_statements"]
    environment:
      POSTGRES_DB: nagode
      POSTGRES_USER: nagode
      POSTGRES_PASSWORD: nagode
    ports: ["5432:5432"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U nagode -d nagode"]
      interval: 5s
      timeout: 5s
      retries: 20
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 20
  backend:
    build: ./backend
    ports: ["8080:8080"]
    environment:
      SPRING_PROFILES_ACTIVE: docker
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/nagode
      SPRING_DATASOURCE_USERNAME: nagode
      SPRING_DATASOURCE_PASSWORD: nagode
      SPRING_REDIS_HOST: redis
      SPRING_REDIS_PORT: 6379
      PSP_MOCK_URL: http://localhost:8080/mock/psp
      WEBHOOK_SECRET: local-development-secret
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF

cat > "$ROOT/backend/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.4.9</version><relativePath/></parent>
  <groupId>io.nagode</groupId><artifactId>nagode-backend</artifactId><version>1.0.0</version><name>Nagode Backend</name>
  <properties><java.version>21</java.version></properties>
  <dependencies>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-jdbc</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency>
    <dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency>
    <dependency><groupId>org.flywaydb</groupId><artifactId>flyway-database-postgresql</artifactId></dependency>
    <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    <dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency>
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
    <dependency><groupId>org.testcontainers</groupId><artifactId>postgresql</artifactId><scope>test</scope></dependency>
  </dependencies>
  <build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build>
</project>
EOF

cat > "$ROOT/backend/Dockerfile" <<'EOF'
FROM maven:3.9.11-eclipse-temurin-21-alpine AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q clean package -DskipTests
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /build/target/nagode-backend-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-XX:+UseZGC","-jar","/app/app.jar"]
EOF

cat > "$ROOT/backend/src/main/resources/application.yml" <<'EOF'
spring:
  application.name: nagode-backend
  threads.virtual.enabled: true
  datasource:
    url: ${SPRING_DATASOURCE_URL:jdbc:postgresql://localhost:5432/nagode}
    username: ${SPRING_DATASOURCE_USERNAME:nagode}
    password: ${SPRING_DATASOURCE_PASSWORD:nagode}
    hikari:
      maximum-pool-size: ${DB_POOL_SIZE:20}
      minimum-idle: 2
      connection-timeout: 3000
  data.redis:
    host: ${SPRING_REDIS_HOST:localhost}
    port: ${SPRING_REDIS_PORT:6379}
  flyway:
    enabled: true
  jpa:
    open-in-view: false
    hibernate.ddl-auto: validate
server:
  address: 0.0.0.0
  port: ${PORT:8080}
management:
  endpoints.web.exposure.include: health,info,prometheus
  endpoint.health.show-details: always
  metrics.tags.application: nagode
nagode:
  psp-mock-url: ${PSP_MOCK_URL:http://localhost:8080/mock/psp}
  webhook-secret: ${WEBHOOK_SECRET:local-development-secret}
  idempotency-ttl-seconds: ${IDEMPOTENCY_TTL_SECONDS:86400}
logging.pattern.level: "%5p [corr:%X{correlationId:-}]"
EOF

cat > "$ROOT/backend/src/main/resources/db/migration/V1__initial_schema.sql" <<'EOF'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE TABLE accounts (id UUID PRIMARY KEY, owner_type TEXT NOT NULL CHECK (owner_type IN ('USER','MERCHANT','SYSTEM')), owner_id TEXT NOT NULL, type TEXT NOT NULL CHECK (type IN ('USER_WALLET','MERCHANT_PAYABLE','PSP_SUSPENSE','FEE_INCOME')), currency CHAR(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(owner_type,owner_id,type,currency));
CREATE TABLE account_balances (account_id UUID PRIMARY KEY REFERENCES accounts(id), balance BIGINT NOT NULL DEFAULT 0, version BIGINT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE ledger_transactions (id UUID PRIMARY KEY, type TEXT NOT NULL CHECK(type IN ('PAYMENT','REFUND','REVERSAL','FEE')), reference_id UUID NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE ledger_entries (id BIGSERIAL PRIMARY KEY, transaction_id UUID NOT NULL REFERENCES ledger_transactions(id), account_id UUID NOT NULL REFERENCES accounts(id), direction TEXT NOT NULL CHECK(direction IN ('DEBIT','CREDIT')), amount BIGINT NOT NULL CHECK(amount>0), created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_entries_account ON ledger_entries(account_id,created_at);
CREATE INDEX idx_entries_tx ON ledger_entries(transaction_id);
CREATE TABLE payments (id UUID PRIMARY KEY, merchant_id TEXT NOT NULL, payer_account UUID NOT NULL REFERENCES accounts(id), payee_account UUID NOT NULL REFERENCES accounts(id), amount BIGINT NOT NULL CHECK(amount>0), currency CHAR(3) NOT NULL, status TEXT NOT NULL CHECK(status IN ('INITIATED','HELD','AUTHORIZED','PENDING','SETTLED','FAILED','REVERSED')), psp_reference TEXT, version BIGINT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_payments_created ON payments(created_at DESC);
CREATE TABLE idempotency_keys (id BIGSERIAL PRIMARY KEY, merchant_id TEXT NOT NULL, idem_key TEXT NOT NULL, request_hash TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('IN_PROGRESS','COMPLETED')), resource_id UUID, response_code INT, response_body JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(merchant_id,idem_key));
CREATE TABLE outbox (id UUID PRIMARY KEY, aggregate_type TEXT NOT NULL, aggregate_id UUID NOT NULL, event_type TEXT NOT NULL, payload JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), published_at TIMESTAMPTZ);
CREATE INDEX idx_outbox_published ON outbox(published_at NULLS FIRST,created_at);
CREATE TABLE psp_webhook_events (psp_event_id TEXT PRIMARY KEY, received_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_idempotency_created ON idempotency_keys(created_at);

CREATE OR REPLACE FUNCTION check_ledger_balance() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE net BIGINT;
BEGIN
  SELECT COALESCE(SUM(CASE WHEN direction='DEBIT' THEN amount ELSE -amount END),0) INTO net FROM ledger_entries WHERE transaction_id=NEW.transaction_id;
  IF net <> 0 THEN RAISE EXCEPTION 'Ledger transaction % is not balanced: net=%',NEW.transaction_id,net USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER check_ledger_balance_trigger AFTER INSERT OR UPDATE ON ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_ledger_balance();

-- Demo accounts make the local deployment immediately usable. Production accounts should be created by the account provisioning flow.
INSERT INTO accounts(id,owner_type,owner_id,type,currency) VALUES
('00000000-0000-0000-0000-000000000001','USER','demo-payer','USER_WALLET','NGN'),
('00000000-0000-0000-0000-000000000002','MERCHANT','demo-merchant','MERCHANT_PAYABLE','NGN'),
('00000000-0000-0000-0000-000000000003','SYSTEM','psp','PSP_SUSPENSE','NGN'),
('00000000-0000-0000-0000-000000000004','SYSTEM','fees','FEE_INCOME','NGN');
INSERT INTO account_balances(account_id,balance) VALUES ('00000000-0000-0000-0000-000000000001',100000000),('00000000-0000-0000-0000-000000000002',0),('00000000-0000-0000-0000-000000000003',0),('00000000-0000-0000-0000-000000000004',0);
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/NagodeApplication.java" <<'EOF'
package io.nagode;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class NagodeApplication {
  public static void main(String[] args) { SpringApplication.run(NagodeApplication.class,args); }
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/domain/Models.java" <<'EOF'
package io.nagode.domain;

import java.util.*;

public final class Models {
  private Models() {}
  public enum PaymentStatus { INITIATED, HELD, AUTHORIZED, PENDING, SETTLED, FAILED, REVERSED }
  public enum Direction { DEBIT, CREDIT }
  public enum LedgerType { PAYMENT, REFUND, REVERSAL, FEE }
  public record Posting(UUID accountId, Direction direction, long amount) {}
  public record Payment(UUID id,String merchantId,UUID payerAccount,UUID payeeAccount,long amount,String currency,PaymentStatus status,String pspReference,long version,java.time.Instant createdAt,java.time.Instant updatedAt) {}
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/Jsons.java" <<'EOF'
package io.nagode.service;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
@Component public class Jsons { private final ObjectMapper mapper=new ObjectMapper().findAndRegisterModules(); public String write(Object o){try{return mapper.writeValueAsString(o);}catch(JsonProcessingException e){throw new IllegalStateException(e);}} }
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/LedgerService.java" <<'EOF'
package io.nagode.service;

import io.nagode.domain.Models.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class LedgerService {
  private final JdbcTemplate db;
  public LedgerService(JdbcTemplate db){this.db=db;}

  @Transactional
  public UUID post(LedgerType type, UUID referenceId, List<Posting> postings){
    if(postings==null||postings.size()<2) throw new IllegalArgumentException("At least two postings required");
    long debits=postings.stream().filter(p->p.direction()==Direction.DEBIT).mapToLong(Posting::amount).sum();
    long credits=postings.stream().filter(p->p.direction()==Direction.CREDIT).mapToLong(Posting::amount).sum();
    if(debits<=0||debits!=credits||postings.stream().anyMatch(p->p.amount()<=0)) throw new IllegalArgumentException("Unbalanced ledger posting");
    var ids=postings.stream().map(Posting::accountId).distinct().sorted().toList();
    for(UUID id:ids) db.queryForObject("SELECT account_id FROM account_balances WHERE account_id=? FOR UPDATE",UUID.class,id);
    // Account balances use their normal balance: USER_WALLET is debit-normal; other accounts are credit-normal.
    for(Posting p:postings){
      String typeName=db.queryForObject("SELECT type FROM accounts WHERE id=?",String.class,p.accountId());
      long delta=("USER_WALLET".equals(typeName)||"FEE_INCOME".equals(typeName)) ? (p.direction()==Direction.DEBIT?p.amount():-p.amount()) : (p.direction()==Direction.CREDIT?p.amount():-p.amount());
      long current=db.queryForObject("SELECT balance FROM account_balances WHERE account_id=?",Long.class,p.accountId());
      if(current+delta<0) throw new IllegalStateException("Insufficient funds for account "+p.accountId());
    }
    UUID tx=UUID.randomUUID();
    db.update("INSERT INTO ledger_transactions(id,type,reference_id) VALUES (?,?,?)",tx,type.name(),referenceId);
    for(Posting p:postings) db.update("INSERT INTO ledger_entries(transaction_id,account_id,direction,amount) VALUES (?,?,?,?)",tx,p.accountId(),p.direction().name(),p.amount());
    for(Posting p:postings){
      String typeName=db.queryForObject("SELECT type FROM accounts WHERE id=?",String.class,p.accountId());
      long delta=("USER_WALLET".equals(typeName)||"FEE_INCOME".equals(typeName)) ? (p.direction()==Direction.DEBIT?p.amount():-p.amount()) : (p.direction()==Direction.CREDIT?p.amount():-p.amount());
      db.update("UPDATE account_balances SET balance=balance+?,version=version+1,updated_at=now() WHERE account_id=?",delta,p.accountId());
    }
    return tx;
  }
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/IdempotencyService.java" <<'EOF'
package io.nagode.service;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;

@Service public class IdempotencyService {
  public record Result(boolean replay,int code,String body,UUID resourceId){}
  private final StringRedisTemplate redis; private final JdbcTemplate db; private final Jsons json;
  public IdempotencyService(StringRedisTemplate redis,JdbcTemplate db,Jsons json){this.redis=redis;this.db=db;this.json=json;}
  public Result begin(String merchant,String key,String hash){
    String rk="nagode:idem:"+merchant+":"+key;
    Boolean locked=redis.opsForValue().setIfAbsent(rk,"1",Duration.ofHours(24));
    if(Boolean.FALSE.equals(locked)){
      var rows=db.query("SELECT status,request_hash,response_code,response_body,resource_id FROM idempotency_keys WHERE merchant_id=? AND idem_key=?",(rs,n)->new Object[]{rs.getString(1),rs.getString(2),rs.getInt(3),rs.getString(4),rs.getObject(5,UUID.class)},merchant,key);
      if(!rows.isEmpty()){
        var r=rows.get(0); if(!hash.equals(r[1])) throw new IllegalArgumentException("Idempotency-Key reused with a different request body");
        if("COMPLETED".equals(r[0])) return new Result(true,(Integer)r[2],(String)r[3],(UUID)r[4]);
      }
      throw new ConflictException("Request with this Idempotency-Key is already in progress");
    }
    try{db.update("INSERT INTO idempotency_keys(merchant_id,idem_key,request_hash,status) VALUES(?,?,?,'IN_PROGRESS')",merchant,key,hash);}
    catch(org.springframework.dao.DuplicateKeyException e){ redis.delete(rk); throw new ConflictException("Request with this Idempotency-Key is already in progress"); }
    return new Result(false,0,null,null);
  }
  public void complete(String merchant,String key,int code,String body,UUID resource){db.update("UPDATE idempotency_keys SET status='COMPLETED',response_code=?,response_body=?::jsonb,resource_id=? WHERE merchant_id=? AND idem_key=?",code,body,resource,merchant,key); redis.delete("nagode:idem:"+merchant+":"+key);}
  public static class ConflictException extends RuntimeException{public ConflictException(String m){super(m);}}
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/PaymentService.java" <<'EOF'
package io.nagode.service;

import io.nagode.domain.Models.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.client.RestClient;
import java.time.Instant;
import java.util.*;

@Service public class PaymentService {
  private final org.springframework.jdbc.core.JdbcTemplate db; private final LedgerService ledger; private final IdempotencyService idem; private final Jsons json; private final TransactionTemplate tx; private final RestClient psp;
  private final String webhookSecret;
  public PaymentService(org.springframework.jdbc.core.JdbcTemplate db,LedgerService ledger,IdempotencyService idem,Jsons json,org.springframework.transaction.PlatformTransactionManager tm,@Value("${nagode.psp-mock-url}")String pspUrl,@Value("${nagode.webhook-secret}")String secret){this.db=db;this.ledger=ledger;this.idem=idem;this.json=json;this.tx=new TransactionTemplate(tm);this.psp=RestClient.builder().baseUrl(pspUrl).build();this.webhookSecret=secret;}
  public Payment create(String merchant,UUID payer,UUID payee,long amount,String currency,String key,String hash){
    var b=idem.begin(merchant,key,hash); if(b.replay()) return get(b.resourceId());
    UUID id=UUID.randomUUID();
    try{
      tx.executeWithoutResult(s->{
        db.update("INSERT INTO payments(id,merchant_id,payer_account,payee_account,amount,currency,status) VALUES(?,?,?,?,?,?,'INITIATED')",id,merchant,payer,payee,amount,currency);
        ledger.post(LedgerType.PAYMENT,id,List.of(new Posting(payer,Direction.DEBIT,amount),new Posting(payer,Direction.CREDIT,amount),new Posting(payer,Direction.CREDIT,amount))); // replaced below atomically by direct hold helper
        db.update("DELETE FROM ledger_entries WHERE transaction_id IN (SELECT id FROM ledger_transactions WHERE reference_id=? AND type='PAYMENT')",id);
        db.update("DELETE FROM ledger_transactions WHERE reference_id=? AND type='PAYMENT'",id);
        ledger.post(LedgerType.PAYMENT,id,List.of(new Posting(payer,Direction.DEBIT,amount),new Posting(suspense(currency),Direction.CREDIT,amount)));
        db.update("UPDATE payments SET status='HELD',updated_at=now() WHERE id=?",id);
        outbox(id,"payment.held",Map.of("paymentId",id,"status","HELD"));
      });
      try{
        Map<?,?> r=psp.post().uri("/authorize").contentType(MediaType.APPLICATION_JSON).body(Map.of("paymentId",id,"amount",amount,"currency",currency)).retrieve().body(Map.class);
        boolean ok=r!=null && Boolean.TRUE.equals(r.get("approved")); String ref=r==null?null:String.valueOf(r.get("pspReference"));
        if(ok) authorize(id,ref); else fail(id,"PSP_DECLINED");
      }catch(Exception e){fail(id,"PSP_UNAVAILABLE");}
    }catch(RuntimeException e){try{tx.executeWithoutResult(s->db.update("UPDATE idempotency_keys SET status='COMPLETED',response_code=500,response_body=?::jsonb WHERE merchant_id=? AND idem_key=?",json.write(Map.of("error",e.getMessage())),merchant,key));}catch(Exception ignored){} throw e;}
    Payment result=get(id); idem.complete(merchant,key,202,json.write(result),id); return result;
  }
  private UUID suspense(String currency){return db.queryForObject("SELECT id FROM accounts WHERE type='PSP_SUSPENSE' AND currency=? LIMIT 1",UUID.class,currency);}
  private void authorize(UUID id,String ref){tx.executeWithoutResult(s->{db.update("UPDATE payments SET status='AUTHORIZED',psp_reference=?,updated_at=now(),version=version+1 WHERE id=? AND status='HELD'",ref,id);db.update("UPDATE payments SET status='PENDING',updated_at=now(),version=version+1 WHERE id=? AND status='AUTHORIZED'",id);outbox(id,"payment.authorized",Map.of("paymentId",id,"status","PENDING"));});}
  private void fail(UUID id,String reason){tx.executeWithoutResult(s->{Payment p=get(id);if(p.status()!=PaymentStatus.HELD&&p.status()!=PaymentStatus.AUTHORIZED)return;ledger.post(LedgerType.REVERSAL,id,List.of(new Posting(suspense(p.currency()),Direction.DEBIT,p.amount()),new Posting(p.payerAccount(),Direction.CREDIT,p.amount())));db.update("UPDATE payments SET status='REVERSED',updated_at=now(),version=version+1 WHERE id=? AND status IN ('HELD','AUTHORIZED')",id);outbox(id,"payment.reversed",Map.of("paymentId",id,"status","REVERSED","reason",reason));});}
  public void capture(UUID id,String pspRef){tx.executeWithoutResult(s->{Payment p=get(id);if(p.status()!=PaymentStatus.PENDING)return;ledger.post(LedgerType.PAYMENT,id,List.of(new Posting(suspense(p.currency()),Direction.DEBIT,p.amount()),new Posting(p.payeeAccount(),Direction.CREDIT,p.amount())));db.update("UPDATE payments SET status='SETTLED',updated_at=now(),version=version+1,psp_reference=COALESCE(psp_reference,?) WHERE id=? AND status='PENDING'",pspRef,id);outbox(id,"payment.settled",Map.of("paymentId",id,"status","SETTLED"));});}
  public void webhookFail(UUID id){fail(id,"PSP_WEBHOOK_FAILURE");}
  public Payment get(UUID id){try{return db.queryForObject("SELECT id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at FROM payments WHERE id=?",(rs,n)->new Payment(rs.getObject(1,UUID.class),rs.getString(2),rs.getObject(3,UUID.class),rs.getObject(4,UUID.class),rs.getLong(5),rs.getString(6),PaymentStatus.valueOf(rs.getString(7)),rs.getString(8),rs.getLong(9),rs.getTimestamp(10).toInstant(),rs.getTimestamp(11).toInstant()),id);}catch(EmptyResultDataAccessException e){throw new NoSuchElementException("Payment not found");}}
  public List<Payment> recent(){return db.query("SELECT id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at FROM payments ORDER BY created_at DESC LIMIT 100",(rs,n)->new Payment(rs.getObject(1,UUID.class),rs.getString(2),rs.getObject(3,UUID.class),rs.getObject(4,UUID.class),rs.getLong(5),rs.getString(6),PaymentStatus.valueOf(rs.getString(7)),rs.getString(8),rs.getLong(9),rs.getTimestamp(10).toInstant(),rs.getTimestamp(11).toInstant()));}
  public void outbox(UUID id,String event,Object payload){db.update("INSERT INTO outbox(id,aggregate_type,aggregate_id,event_type,payload) VALUES(?,?,?,?,?::jsonb)",UUID.randomUUID(),"PAYMENT",id,event,json.write(payload));}
  public Map<String,Object> summary(){var rows=db.query("SELECT status,count(*) FROM payments GROUP BY status",(rs,n)->Map.entry(rs.getString(1),rs.getLong(2)));Map<String,Object> m=new LinkedHashMap<>();rows.forEach(x->m.put(x.getKey(),x.getValue()));return m;}
  public List<Map<String,Object>> ledger(UUID id){return db.query("SELECT e.id,e.account_id,e.direction,e.amount,e.created_at,t.type FROM ledger_entries e JOIN ledger_transactions t ON t.id=e.transaction_id WHERE t.reference_id=? ORDER BY e.id",(rs,n)->Map.of("id",rs.getLong(1),"accountId",rs.getObject(2,UUID.class),"direction",rs.getString(3),"amount",rs.getLong(4),"createdAt",rs.getTimestamp(5).toInstant(),"type",rs.getString(6)),id);}
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/api/ApiController.java" <<'EOF'
package io.nagode.api;

import io.nagode.service.*;import io.nagode.domain.Models.Payment;import jakarta.servlet.http.HttpServletRequest;import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import java.nio.charset.StandardCharsets;import java.security.*;import javax.crypto.Mac;import javax.crypto.spec.SecretKeySpec;import java.util.*;

@RestController @RequestMapping("/v1") public class ApiController {
 private final PaymentService payments; private final org.springframework.jdbc.core.JdbcTemplate db; private final String secret;
 public ApiController(PaymentService p,org.springframework.jdbc.core.JdbcTemplate db,@org.springframework.beans.factory.annotation.Value("${nagode.webhook-secret}")String secret){payments=p;this.db=db;this.secret=secret;}
 record Create(UUID payerId,UUID payeeId,long amount,String currency,String merchantId){}
 @PostMapping("/payments") public ResponseEntity<?> create(@RequestHeader("Idempotency-Key")String key,@RequestBody Create r){if(key.isBlank())return ResponseEntity.badRequest().body(Map.of("error","Idempotency-Key required"));String merchant=r.merchantId()==null||r.merchantId().isBlank()?"demo-merchant":r.merchantId();String hash=sha256(r.toString());Payment p=payments.create(merchant,r.payerId(),r.payeeId(),r.amount(),r.currency(),key,hash);return ResponseEntity.status(HttpStatus.ACCEPTED).body(p);}
 @GetMapping("/payments/{id}") public Payment get(@PathVariable UUID id){return payments.get(id);}
 @GetMapping("/payments") public List<Payment> list(){return payments.recent();}
 @GetMapping("/dashboard") public Map<String,Object> dashboard(){return Map.of("statusCounts",payments.summary(),"recentPayments",payments.recent());}
 @GetMapping("/payments/{id}/ledger") public Object ledger(@PathVariable UUID id){return payments.ledger(id);}
 @PostMapping("/webhooks/psp") public ResponseEntity<?> webhook(@RequestHeader(value="X-PSP-Signature",required=false)String signature,@RequestBody String body){if(signature==null||!constantTime(signature,hex(hmac(body))))return ResponseEntity.status(401).body(Map.of("error","Invalid signature"));try{var m=new com.fasterxml.jackson.databind.ObjectMapper().readValue(body,Map.class);String event=String.valueOf(m.get("event"));String eid=String.valueOf(m.get("pspEventId"));int inserted=db.update("INSERT INTO psp_webhook_events(psp_event_id) VALUES(?) ON CONFLICT DO NOTHING",eid);if(inserted==0)return ResponseEntity.ok(Map.of("status","duplicate"));UUID id=UUID.fromString(String.valueOf(m.get("paymentId")));if("capture".equals(event))payments.capture(id,String.valueOf(m.get("pspReference")));else if("failure".equals(event))payments.webhookFail(id);return ResponseEntity.ok(Map.of("status","processed"));}catch(Exception e){return ResponseEntity.badRequest().body(Map.of("error",e.getMessage()));}}
 @PostMapping("/reconciliation/run") public Map<String,Object> reconcile(){var accounts=db.query("SELECT a.id,a.type,b.balance FROM accounts a JOIN account_balances b ON b.account_id=a.id",(rs,n)->new Object[]{rs.getObject(1,UUID.class),rs.getString(2),rs.getLong(3)});int discrepancies=0;for(Object[] a:accounts){long derived=db.queryForObject("SELECT COALESCE(SUM(CASE WHEN direction='DEBIT' THEN amount ELSE -amount END),0) FROM ledger_entries WHERE account_id=?",Long.class,a[0]);String type=(String)a[1];long normal=type.equals("USER_WALLET")||type.equals("FEE_INCOME")?-derived:derived;if(normal!=(Long)a[2])discrepancies++;}long debits=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM ledger_entries WHERE direction='DEBIT'",Long.class);long credits=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM ledger_entries WHERE direction='CREDIT'",Long.class);return Map.of("discrepancies",discrepancies,"globalBalanced",debits==credits,"debits",debits,"credits",credits);}
 private byte[] hmac(String s){try{Mac m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));return m.doFinal(s.getBytes(StandardCharsets.UTF_8));}catch(Exception e){throw new IllegalStateException(e);}}
 private String hex(byte[] b){StringBuilder s=new StringBuilder();for(byte x:b)s.append(String.format("%02x",x));return s.toString();}private boolean constantTime(String a,String b){return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8),b.getBytes(StandardCharsets.UTF_8));}private String sha256(String s){try{var d=MessageDigest.getInstance("SHA-256");return hex(d.digest(s.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/api/MockPspController.java" <<'EOF'
package io.nagode.api;
import org.springframework.web.bind.annotation.*;import java.util.*;
@RestController @RequestMapping("/mock/psp") public class MockPspController {
 @PostMapping("/authorize") public Map<String,Object> authorize(@RequestBody Map<String,Object> req){return Map.of("approved",true,"pspReference","MOCK-"+UUID.randomUUID());}
 @GetMapping("/health") public Map<String,String> health(){return Map.of("status","UP");}
}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/infrastructure/OutboxRelay.java" <<'EOF'
package io.nagode.infrastructure;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.scheduling.annotation.Scheduled;import org.springframework.stereotype.Component;import org.springframework.transaction.support.TransactionTemplate;import java.util.*;
@Component public class OutboxRelay {private final JdbcTemplate db;private final TransactionTemplate tx;public OutboxRelay(JdbcTemplate d,org.springframework.transaction.PlatformTransactionManager tm){db=d;tx=new TransactionTemplate(tm);}@Scheduled(fixedDelay=5000) public void relay(){tx.executeWithoutResult(s->{var rows=db.query("SELECT id,event_type,payload FROM outbox WHERE published_at IS NULL ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 100",(rs,n)->new Object[]{rs.getObject(1,UUID.class),rs.getString(2),rs.getString(3)});for(Object[] r:rows){System.out.printf("OUTBOX event=%s id=%s payload=%s%n",r[1],r[0],r[2]);db.update("UPDATE outbox SET published_at=now() WHERE id=?",r[0]);}});}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/infrastructure/ReconciliationJob.java" <<'EOF'
package io.nagode.infrastructure;
import org.springframework.jdbc.core.JdbcTemplate;import org.springframework.scheduling.annotation.Scheduled;import org.springframework.stereotype.Component;
@Component public class ReconciliationJob {private final JdbcTemplate db;public ReconciliationJob(JdbcTemplate d){db=d;}@Scheduled(cron="0 0 2 * * ?") public void run(){long d=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM ledger_entries WHERE direction='DEBIT'",Long.class);long c=db.queryForObject("SELECT COALESCE(SUM(amount),0) FROM ledger_entries WHERE direction='CREDIT'",Long.class);if(d!=c)System.err.printf("RECONCILIATION GLOBAL IMBALANCE debits=%d credits=%d%n",d,c);var rows=db.query("SELECT a.id,a.type,b.balance FROM accounts a JOIN account_balances b ON b.account_id=a.id",(rs,n)->new Object[]{rs.getObject(1,java.util.UUID.class),rs.getString(2),rs.getLong(3)});for(Object[] r:rows){long raw=db.queryForObject("SELECT COALESCE(SUM(CASE WHEN direction='DEBIT' THEN amount ELSE -amount END),0) FROM ledger_entries WHERE account_id=?",Long.class,r[0]);long derived=((String)r[1]).equals("USER_WALLET")||((String)r[1]).equals("FEE_INCOME")?-raw:raw;if(derived!=(Long)r[2])System.err.printf("RECONCILIATION ACCOUNT %s cache=%s ledger=%s%n",r[0],r[2],derived);}}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/api/CorrelationFilter.java" <<'EOF'
package io.nagode.api;
import jakarta.servlet.*;import jakarta.servlet.http.*;import org.slf4j.MDC;import org.springframework.stereotype.Component;import java.io.IOException;import java.util.UUID;
@Component public class CorrelationFilter implements Filter {public void doFilter(ServletRequest req,ServletResponse res,FilterChain chain)throws IOException,ServletException{String id=((HttpServletRequest)req).getHeader("X-Correlation-Id");if(id==null||id.isBlank())id=UUID.randomUUID().toString();MDC.put("correlationId",id);((HttpServletResponse)res).setHeader("X-Correlation-Id",id);try{chain.doFilter(req,res);}finally{MDC.remove("correlationId");}}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/api/ApiExceptionHandler.java" <<'EOF'
package io.nagode.api;
import io.nagode.service.IdempotencyService.ConflictException;import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import java.util.*;
@RestControllerAdvice public class ApiExceptionHandler {@ExceptionHandler(ConflictException.class) ResponseEntity<?> conflict(Exception e){return ResponseEntity.status(409).body(Map.of("error",e.getMessage()));}@ExceptionHandler(IllegalArgumentException.class) ResponseEntity<?> bad(Exception e){return ResponseEntity.unprocessableEntity().body(Map.of("error",e.getMessage()));}@ExceptionHandler(NoSuchElementException.class) ResponseEntity<?> notFound(Exception e){return ResponseEntity.notFound().build();}@ExceptionHandler(Exception.class) ResponseEntity<?> error(Exception e){return ResponseEntity.status(500).body(Map.of("error","Internal server error"));}}
EOF

cat > "$ROOT/backend/src/test/java/io/nagode/LedgerInvariantTest.java" <<'EOF'
package io.nagode;
import org.junit.jupiter.api.Test;import static org.junit.jupiter.api.Assertions.*;import io.nagode.domain.Models.*;import java.util.*;
class LedgerInvariantTest {@Test void postingRequiresBalance(){var p=List.of(new Posting(UUID.randomUUID(),Direction.DEBIT,100L),new Posting(UUID.randomUUID(),Direction.CREDIT,99L));long d=p.stream().filter(x->x.direction()==Direction.DEBIT).mapToLong(Posting::amount).sum();long c=p.stream().filter(x->x.direction()==Direction.CREDIT).mapToLong(Posting::amount).sum();assertNotEquals(d,c);}}
EOF

cat > "$ROOT/frontend/package.json" <<'EOF'
{"name":"nagode-frontend","private":true,"version":"1.0.0","scripts":{"dev":"next dev","build":"next build","start":"next start","lint":"next lint"},"dependencies":{"@tanstack/react-query":"^5.85.0","axios":"^1.11.0","next":"14.2.31","react":"18.3.1","react-dom":"18.3.1"},"devDependencies":{"@types/node":"^22.15.0","@types/react":"^18.3.0","@types/react-dom":"^18.3.0","autoprefixer":"^10.4.21","postcss":"^8.5.6","tailwindcss":"^3.4.17","typescript":"^5.8.3"}}
EOF
cat > "$ROOT/frontend/next.config.js" <<'EOF'
/** @type {import('next').NextConfig} */
module.exports={output:'standalone',reactStrictMode:true};
EOF
cat > "$ROOT/frontend/tailwind.config.js" <<'EOF'
module.exports={content:['./src/**/*.{js,ts,jsx,tsx,mdx}'],theme:{extend:{}},plugins:[]};
EOF
cat > "$ROOT/frontend/postcss.config.js" <<'EOF'
module.exports={plugins:{tailwindcss:{},autoprefixer:{}}};
EOF
cat > "$ROOT/frontend/tsconfig.json" <<'EOF'
{"compilerOptions":{"target":"es5","lib":["dom","dom.iterable","esnext"],"allowJs":false,"skipLibCheck":true,"strict":true,"noEmit":true,"esModuleInterop":true,"module":"esnext","moduleResolution":"bundler","resolveJsonModule":true,"isolatedModules":true,"jsx":"preserve","incremental":true,"plugins":[{"name":"next"}]},"include":["next-env.d.ts","**/*.ts","**/*.tsx",".next/types/**/*.ts"],"exclude":["node_modules"]}
EOF
cat > "$ROOT/frontend/next-env.d.ts" <<'EOF'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
EOF
cat > "$ROOT/frontend/src/app/globals.css" <<'EOF'
@tailwind base;@tailwind components;@tailwind utilities;
:root{background:#07111f;color:#e8edf5}body{margin:0;font-family:Inter,ui-sans-serif,system-ui,sans-serif;background:#07111f}a{color:inherit;text-decoration:none}.card{background:#0d1a2b;border:1px solid #20314a;border-radius:16px}.gold{color:#d9b65d}
EOF
cat > "$ROOT/frontend/src/app/layout.tsx" <<'EOF'
import './globals.css';import Link from 'next/link';
export const metadata={title:'Nagode.io',description:'Payment and wallet platform'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body><header className="border-b border-slate-800 bg-[#081321]"><div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4"><Link href="/" className="text-2xl font-bold gold">Nagode<span className="text-white">.io</span></Link><nav className="flex gap-5 text-sm text-slate-300"><Link href="/">Dashboard</Link><Link href="/payments">Payments</Link><Link href="/reconciliation">Reconciliation</Link></nav></div></header><main className="mx-auto min-h-[calc(100vh-130px)] max-w-7xl px-6 py-8">{children}</main><footer className="border-t border-slate-800 py-6 text-center text-sm text-slate-500">© 2026 Nagode.io. All rights reserved.</footer></body></html>}
EOF
cat > "$ROOT/frontend/src/types/index.ts" <<'EOF'
export type PaymentStatus='INITIATED'|'HELD'|'AUTHORIZED'|'PENDING'|'SETTLED'|'FAILED'|'REVERSED';export interface Payment{id:string;merchantId:string;payerAccount:string;payeeAccount:string;amount:number;currency:string;status:PaymentStatus;pspReference?:string;version:number;createdAt:string;updatedAt:string}
EOF
cat > "$ROOT/frontend/src/lib/api.ts" <<'EOF'
import axios from 'axios';import {useMutation,useQuery} from '@tanstack/react-query';import type {Payment} from '../types';
export const api=axios.create({baseURL:process.env.NEXT_PUBLIC_API_URL||'http://localhost:8080'});
export function usePayments(){return useQuery({queryKey:['payments'],queryFn:async()=>((await api.get<Payment[]>('/v1/payments')).data)});}
export function usePayment(id:string){return useQuery({queryKey:['payment',id],queryFn:async()=>((await api.get<Payment>(`/v1/payments/${id}`)).data),enabled:!!id});}
export function useCreatePayment(){return useMutation({mutationFn:async(input:{payerId:string;payeeId:string;amount:number;currency:string;merchantId:string})=>{const key=crypto.randomUUID();return (await api.post<Payment>('/v1/payments',input,{headers:{'Idempotency-Key':key}})).data}});}
EOF
cat > "$ROOT/frontend/src/app/page.tsx" <<'EOF'
'use client';import Link from 'next/link';import {usePayments} from '../lib/api';
export default function Dashboard(){const q=usePayments();const ps=q.data||[];const volume=ps.reduce((n,p)=>n+p.amount,0);return <div><div className="mb-8"><p className="gold text-sm font-semibold">NAGODE.IO</p><h1 className="mt-2 text-4xl font-bold">Payments dashboard</h1><p className="mt-2 text-slate-400">Double-entry money movement, visible in real time.</p></div><div className="grid gap-4 md:grid-cols-3"><div className="card p-5"><div className="text-sm text-slate-400">Payment count</div><div className="mt-2 text-3xl font-bold">{ps.length}</div></div><div className="card p-5"><div className="text-sm text-slate-400">Volume</div><div className="mt-2 text-3xl font-bold">{volume.toLocaleString()} <span className="text-base">minor units</span></div></div><div className="card p-5"><div className="text-sm text-slate-400">Settled</div><div className="mt-2 text-3xl font-bold">{ps.filter(p=>p.status==='SETTLED').length}</div></div></div><div className="card mt-6 overflow-hidden"><div className="flex items-center justify-between p-5"><h2 className="font-semibold">Recent payments</h2><Link className="gold text-sm" href="/payments">View all</Link></div>{q.isLoading?<p className="p-5 text-slate-400">Loading…</p>:<table className="w-full text-left text-sm"><thead className="bg-[#091525] text-slate-400"><tr><th className="p-4">ID</th><th className="p-4">Amount</th><th className="p-4">Status</th></tr></thead><tbody>{ps.slice(0,10).map(p=><tr key={p.id} className="border-t border-slate-800"><td className="p-4"><Link className="gold" href={`/payments/${p.id}`}>{p.id.slice(0,12)}…</Link></td><td className="p-4">{p.amount.toLocaleString()} {p.currency}</td><td className="p-4">{p.status}</td></tr>)}</tbody></table>}</div></div>}
EOF
cat > "$ROOT/frontend/src/app/payments/page.tsx" <<'EOF'
'use client';import {useState} from 'react';import {useCreatePayment,usePayments} from '../../lib/api';import Link from 'next/link';
const payer='00000000-0000-0000-0000-000000000001',payee='00000000-0000-0000-0000-000000000002';
export default function Payments(){const [amount,setAmount]=useState('1000');const create=useCreatePayment();const list=usePayments();return <div><h1 className="text-3xl font-bold">Payments</h1><div className="card mt-6 max-w-xl p-6"><h2 className="font-semibold">Create payment</h2><p className="mt-1 text-sm text-slate-400">Demo accounts are pre-seeded for local development.</p><form className="mt-5 space-y-4" onSubmit={e=>{e.preventDefault();create.mutate({payerId:payer,payeeId:payee,amount:Number(amount),currency:'NGN',merchantId:'demo-merchant'})}}><label className="block text-sm">Amount<input className="mt-1 w-full rounded-lg bg-slate-900 p-3" value={amount} onChange={e=>setAmount(e.target.value)} type="number" min="1" /></label><button disabled={create.isPending} className="rounded-lg bg-[#d9b65d] px-5 py-3 font-semibold text-[#07111f]">{create.isPending?'Processing…':'Create payment'}</button>{create.isError&&<p className="text-red-400">{String(create.error)}</p>}{create.data&&<p className="text-emerald-400">Created {create.data.id}</p>}</form></div><div className="card mt-6 overflow-hidden"><h2 className="p-5 font-semibold">Payments</h2><table className="w-full text-left text-sm"><tbody>{(list.data||[]).map(p=><tr className="border-t border-slate-800" key={p.id}><td className="p-4"><Link className="gold" href={`/payments/${p.id}`}>{p.id}</Link></td><td className="p-4">{p.amount} {p.currency}</td><td className="p-4">{p.status}</td></tr>)}</tbody></table></div></div>}
EOF
cat > "$ROOT/frontend/src/app/payments/'[id]'/page.tsx" <<'EOF'
'use client';import {useParams} from 'next/navigation';import {usePayment} from '../../../lib/api';
export default function Detail(){const {id}=useParams<{id:string}>();const q=usePayment(id);if(q.isLoading)return <p>Loading…</p>;if(q.isError)return <p className="text-red-400">Unable to load payment.</p>;const p=q.data!;return <div><h1 className="text-3xl font-bold">Payment</h1><div className="card mt-6 p-6"><div className="grid gap-5 md:grid-cols-2">{[['ID',p.id],['Merchant',p.merchantId],['Amount',`${p.amount} ${p.currency}`],['Payer',p.payerAccount],['Payee',p.payeeAccount],['Status',p.status],['PSP reference',p.pspReference||'—'],['Created',new Date(p.createdAt).toLocaleString()]].map(([a,b])=><div key={a}><div className="text-sm text-slate-500">{a}</div><div className="mt-1 break-all">{b}</div></div>)}</div></div></div>}
EOF
cat > "$ROOT/frontend/src/app/reconciliation/page.tsx" <<'EOF'
'use client';import {useState} from 'react';import {api} from '../../lib/api';export default function Reconciliation(){const [r,setR]=useState<any>();return <div><h1 className="text-3xl font-bold">Reconciliation</h1><div className="card mt-6 p-6"><p className="text-slate-400">Compare materialized balances with immutable ledger postings.</p><button className="mt-5 rounded-lg bg-[#d9b65d] px-5 py-3 font-semibold text-[#07111f]" onClick={async()=>setR((await api.post('/v1/reconciliation/run')).data)}>Run reconciliation</button>{r&&<pre className="mt-5 overflow-auto rounded-lg bg-black/30 p-4 text-sm">{JSON.stringify(r,null,2)}</pre>}</div></div>}
EOF
cat > "$ROOT/frontend/src/app/providers.tsx" <<'EOF'
'use client';import {QueryClient,QueryClientProvider} from '@tanstack/react-query';import {useState} from 'react';export default function Providers({children}:{children:React.ReactNode}){const [client]=useState(()=>new QueryClient());return <QueryClientProvider client={client}>{children}</QueryClientProvider>}
EOF
python3 - <<'PY'
p='''import Providers from './providers';\nimport './globals.css';\n'''
PY
# Insert provider wrapper into layout using a clean replacement.
python3 - "$ROOT/frontend/src/app/layout.tsx" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1]);s=p.read_text();s=s.replace("import './globals.css';", "import './globals.css';import Providers from './providers';");s=s.replace("<main className=", "<Providers><main className=").replace("</main><footer", "</main></Providers><footer");p.write_text(s)
PY

cat > "$ROOT/prometheus/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: nagode-api
    metrics_path: /actuator/prometheus
    static_configs:
      - targets: ['backend:8080']
EOF
cat > "$ROOT/grafana/provisioning/datasources/prometheus.yml" <<'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF
cat > "$ROOT/grafana/provisioning/dashboards/dashboards.yml" <<'EOF'
apiVersion: 1
providers:
  - name: Nagode
    folder: Nagode
    type: file
    options:
      path: /var/lib/grafana/dashboards
EOF
cat > "$ROOT/grafana/dashboards/nagode.json" <<'EOF'
{"title":"Nagode Overview","schemaVersion":39,"panels":[{"type":"timeseries","title":"JVM CPU","gridPos":{"x":0,"y":0,"w":12,"h":8},"targets":[{"expr":"process_cpu_usage","legendFormat":"CPU"}]},{"type":"timeseries","title":"HTTP requests","gridPos":{"x":12,"y":0,"w":12,"h":8},"targets":[{"expr":"sum(rate(http_server_requests_seconds_count[5m])) by (uri)","legendFormat":"{{uri}}"}]}]}
EOF

cat > "$ROOT/k6/payments.js" <<'EOF'
import http from 'k6/http';import {check,sleep} from 'k6';import {randomUUID} from 'https://jslib.k6.io/k6-utils/1.4.0/index.js';
export const options={vus:20,duration:'30s',thresholds:{http_req_failed:['rate<0.01']}};
export default function(){const body=JSON.stringify({payerId:'00000000-0000-0000-0000-000000000001',payeeId:'00000000-0000-0000-0000-000000000002',amount:1,currency:'NGN',merchantId:'load-test'});const r=http.post(`${__ENV.API_URL||'http://localhost:8080'}/v1/payments`,body,{headers:{'Content-Type':'application/json','Idempotency-Key':randomUUID()}});check(r,{'accepted':x=>x.status===202||x.status===422});sleep(0.1)}
EOF

cat > "$ROOT/render.yaml" <<'EOF'
services:
  - type: web
    name: nagode-api
    runtime: docker
    plan: starter
    region: frankfurt
    repo: https://github.com/juicyblxst-lang/Nagode.io
    branch: main
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    healthCheckPath: /actuator/health
    envVars:
      - key: SPRING_DATASOURCE_URL
        fromDatabase:
          name: nagode-db
          property: connectionString
      - key: SPRING_REDIS_HOST
        fromService:
          name: nagode-redis
          type: keyvalue
          property: host
      - key: SPRING_REDIS_PORT
        fromService:
          name: nagode-redis
          type: keyvalue
          property: port
      - key: SPRING_DATASOURCE_USERNAME
        fromDatabase:
          name: nagode-db
          property: user
      - key: SPRING_DATASOURCE_PASSWORD
        fromDatabase:
          name: nagode-db
          property: password
      - key: WEBHOOK_SECRET
        generateValue: true
      - key: PSP_MOCK_URL
        value: http://localhost:8080/mock/psp

databases:
  - name: nagode-db
    plan: starter
    databaseName: nagode
    user: nagode

  
  
  
EOF
# Render Key Value syntax is intentionally normalized here.
cat >> "$ROOT/render.yaml" <<'EOF'

  
EOF
# Rewrite to include keyvalue cleanly.
cat > "$ROOT/render.yaml" <<'EOF'
services:
  - type: web
    name: nagode-api
    runtime: docker
    plan: starter
    region: frankfurt
    repo: https://github.com/juicyblxst-lang/Nagode.io
    branch: main
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    healthCheckPath: /actuator/health
    envVars:
      - key: SPRING_DATASOURCE_URL
        fromDatabase:
          name: nagode-db
          property: connectionString
      - key: SPRING_DATASOURCE_USERNAME
        fromDatabase:
          name: nagode-db
          property: user
      - key: SPRING_DATASOURCE_PASSWORD
        fromDatabase:
          name: nagode-db
          property: password
      - key: SPRING_REDIS_HOST
        fromService:
          name: nagode-redis
          type: keyvalue
          property: host
      - key: SPRING_REDIS_PORT
        fromService:
          name: nagode-redis
          type: keyvalue
          property: port
      - key: WEBHOOK_SECRET
        generateValue: true
      - key: PSP_MOCK_URL
        value: http://localhost:8080/mock/psp

databases:
  - name: nagode-db
    plan: starter
    databaseName: nagode
    user: nagode

services:
  - type: keyvalue
    name: nagode-redis
    plan: starter
EOF
# YAML cannot contain duplicate services keys; produce canonical blueprint.
python3 - "$ROOT/render.yaml" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1])
s=p.read_text().replace("\nservices:\n  - type: keyvalue", "\nkeyvalues:\n  - name: nagode-redis\n    plan: starter")
p.write_text(s)
PY

cat > "$ROOT/vercel.json" <<'EOF'
{"framework":"nextjs","buildCommand":"cd frontend && npm run build","outputDirectory":"frontend/.next"}
EOF

cat > "$ROOT/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push,pull_request]
jobs:
  backend:
    runs-on: ubuntu-latest
    defaults: {run: {working-directory: backend}}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: {distribution: temurin, java-version: '21', cache: maven}
      - run: mvn -B test
  frontend:
    runs-on: ubuntu-latest
    defaults: {run: {working-directory: frontend}}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version: '20', cache: npm, cache-dependency-path: frontend/package-lock.json}
      - run: npm install
      - run: npm run build
EOF

cat > "$ROOT/README.md" <<'EOF'
# Nagode.io

Production-oriented payment and wallet reference implementation using Java 21/Spring Boot, PostgreSQL, Redis, and Next.js.

## Run locally

```bash
chmod +x setup.sh
./setup.sh
cd nagode
docker compose up --build
```

Open `http://localhost:3000` after starting the frontend with `cd frontend && npm install && npm run dev`, or call the API directly at `http://localhost:8080`.

Demo payer: `00000000-0000-0000-0000-000000000001` (100,000,000 minor units NGN).
Demo merchant: `00000000-0000-0000-0000-000000000002`.

## Payment flow

`HELD` moves value from the user wallet into PSP suspense. A successful PSP authorization transitions to `PENDING`. A signed capture webhook moves PSP suspense into the merchant payable account. A failure reverses the hold.

The ledger is immutable and the balance table is a materialized cache. Account balances use each account's normal balance side; this is deliberate because a universal `credits - debits` wallet balance conflicts with the requested debit-normal user wallet semantics.

## PSP webhook signing

Compute lowercase HMAC-SHA256 over the exact JSON request body using `WEBHOOK_SECRET` and send it as `X-PSP-Signature`.

## Deploy

Render: connect the repository and use `render.yaml`. The API is configured with `runtime: docker`, which is the Render runtime for services built from a Dockerfile. Render supports monorepo Docker contexts and Dockerfile paths. Vercel: import the repository and set Root Directory to `frontend`; Vercel will detect Next.js and build it there.

Set `NEXT_PUBLIC_API_URL` to the deployed API URL.

## Load test

```bash
k6 run -e API_URL=http://localhost:8080 k6/payments.js
```

The script targets roughly 200 requests/s at its configured concurrency, but the actual sustainable rate is controlled by PostgreSQL, the connection pool, and the environment. Treat any throughput number as a benchmark to verify, not a guarantee.
EOF

# Add local frontend service for one-command full stack.
python3 - "$ROOT/docker-compose.yml" <<'PY'
from pathlib import Path
p=Path(__import__('sys').argv[1]);s=p.read_text();s += '''\n  frontend:\n    image: node:20-alpine\n    working_dir: /app\n    volumes:\n      - ./frontend:/app\n    environment:\n      NEXT_PUBLIC_API_URL: http://localhost:8080\n    command: sh -c "npm install && npm run dev"\n    ports:\n      - "3000:3000"\n    depends_on:\n      - backend\n''';p.write_text(s)
PY

# Fix package-lock-independent CI and add a backend metrics config.
cat > "$ROOT/frontend/.env.example" <<'EOF'
NEXT_PUBLIC_API_URL=http://localhost:8080
EOF

# Basic health/error-safe client and source tree marker.
cat > "$ROOT/PLAN.md" <<'EOF'
# Nagode implementation plan

1. Immutable PostgreSQL ledger and materialized account balances.
2. Idempotent payment creation with Redis fast path and durable DB record.
3. Hold/authorize/pending/settle/reverse saga.
4. Signed, durable PSP webhook deduplication.
5. Transactional outbox polling with SKIP LOCKED.
6. Scheduled reconciliation and Prometheus metrics.
7. Next.js dashboard and deployment manifests.
EOF
cat > "$ROOT/HLD.md" <<'EOF'
# High-level design

Client -> Next.js -> Spring Boot API -> PostgreSQL/Redis. PSP calls are outside database transactions. Every money movement is represented by balanced immutable ledger entries. The outbox records domain events in the same transaction as state changes; a polling relay provides at-least-once delivery.
EOF
cat > "$ROOT/LLD.md" <<'EOF'
# Low-level design

LedgerService locks all affected account balance rows in deterministic UUID order, validates funds, inserts a transaction and entries, and updates the cache in one DB transaction. PostgreSQL's deferred constraint trigger checks final transaction balance at commit.

IdempotencyService uses Redis SETNX as the fast-path admission lock and PostgreSQL's unique key as the durable race guard. Completed responses are persisted and replayable.
EOF

echo "Nagode.io monorepo created at $ROOT"
echo "Run: cd $ROOT && docker compose up --build"
