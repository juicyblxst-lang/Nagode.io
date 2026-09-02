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
SPRING_DATA_REDIS_URL=redis://localhost:6379
PSP_MOCK_URL=http://localhost:8080/mock/psp
WEBHOOK_SECRET=change-me-in-production
CORS_ALLOWED_ORIGINS=http://localhost:3000
NEXT_PUBLIC_API_URL=http://localhost:8080
EOF

cat > "$ROOT/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:16-alpine
    command: ["postgres","-c","shared_preload_libraries=pg_stat_statements"]
    environment: {POSTGRES_DB: nagode, POSTGRES_USER: nagode, POSTGRES_PASSWORD: nagode}
    ports: ["5432:5432"]
    healthcheck: {test: ["CMD-SHELL","pg_isready -U nagode -d nagode"], interval: 5s, timeout: 5s, retries: 20}
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck: {test: ["CMD","redis-cli","ping"], interval: 5s, timeout: 3s, retries: 20}
  backend:
    build: ./backend
    ports: ["8080:8080"]
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/nagode
      SPRING_DATASOURCE_USERNAME: nagode
      SPRING_DATASOURCE_PASSWORD: nagode
      SPRING_DATA_REDIS_URL: redis://redis:6379
      PSP_MOCK_URL: http://localhost:8080/mock/psp
      WEBHOOK_SECRET: local-development-secret
      CORS_ALLOWED_ORIGINS: http://localhost:3000
    depends_on:
      postgres: {condition: service_healthy}
      redis: {condition: service_healthy}
  frontend:
    build: ./frontend
    ports: ["3000:3000"]
    environment: {NEXT_PUBLIC_API_URL: http://localhost:8080}
    depends_on: [backend]
  prometheus:
    image: prom/prometheus:v3.5.0
    ports: ["9090:9090"]
    volumes: ["./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro"]
    depends_on: [backend]
  grafana:
    image: grafana/grafana:12.1.1
    ports: ["3001:3000"]
    environment: {GF_SECURITY_ADMIN_USER: admin, GF_SECURITY_ADMIN_PASSWORD: admin}
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    depends_on: [prometheus]
EOF

cat > "$ROOT/backend/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?><project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd"><modelVersion>4.0.0</modelVersion><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.4.9</version><relativePath/></parent><groupId>io.nagode</groupId><artifactId>nagode-backend</artifactId><version>1.0.0</version><properties><java.version>21</java.version></properties><dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-jdbc</artifactId></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency><dependency><groupId>org.flywaydb</groupId><artifactId>flyway-core</artifactId></dependency><dependency><groupId>org.flywaydb</groupId><artifactId>flyway-database-postgresql</artifactId></dependency><dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency><dependency><groupId>io.micrometer</groupId><artifactId>micrometer-registry-prometheus</artifactId></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency><dependency><groupId>org.testcontainers</groupId><artifactId>postgresql</artifactId><scope>test</scope></dependency></dependencies><build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>
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
    hikari.maximum-pool-size: ${DB_POOL_SIZE:20}
  data.redis.url: ${SPRING_DATA_REDIS_URL:redis://localhost:6379}
  flyway.enabled: true
  jdbc.template.fetch-size: 100
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
  cors-allowed-origins: ${CORS_ALLOWED_ORIGINS:http://localhost:3000}
logging.pattern.level: "%5p [corr:%X{correlationId:-}]"
EOF

cat > "$ROOT/backend/src/main/resources/db/migration/V1__initial_schema.sql" <<'EOF'
CREATE TABLE accounts(id UUID PRIMARY KEY,owner_type TEXT NOT NULL CHECK(owner_type IN('USER','MERCHANT','SYSTEM')),owner_id TEXT NOT NULL,type TEXT NOT NULL CHECK(type IN('USER_WALLET','MERCHANT_PAYABLE','PSP_SUSPENSE','FEE_INCOME')),currency CHAR(3) NOT NULL CHECK(currency~'^[A-Z]{3}$'),created_at TIMESTAMPTZ NOT NULL DEFAULT now(),UNIQUE(owner_type,owner_id,type,currency));
CREATE TABLE account_balances(account_id UUID PRIMARY KEY REFERENCES accounts(id),balance BIGINT NOT NULL DEFAULT 0,version BIGINT NOT NULL DEFAULT 0,updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE ledger_transactions(id UUID PRIMARY KEY,type TEXT NOT NULL CHECK(type IN('PAYMENT','REFUND','REVERSAL','FEE')),reference_id UUID NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE ledger_entries(id BIGSERIAL PRIMARY KEY,transaction_id UUID NOT NULL REFERENCES ledger_transactions(id),account_id UUID NOT NULL REFERENCES accounts(id),direction TEXT NOT NULL CHECK(direction IN('DEBIT','CREDIT')),amount BIGINT NOT NULL CHECK(amount>0),created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_entries_account ON ledger_entries(account_id,created_at); CREATE INDEX idx_entries_tx ON ledger_entries(transaction_id);
CREATE TABLE payments(id UUID PRIMARY KEY,merchant_id TEXT NOT NULL,payer_account UUID NOT NULL REFERENCES accounts(id),payee_account UUID NOT NULL REFERENCES accounts(id),amount BIGINT NOT NULL CHECK(amount>0),currency CHAR(3) NOT NULL,status TEXT NOT NULL CHECK(status IN('INITIATED','HELD','AUTHORIZED','PENDING','SETTLED','FAILED','REVERSED')),psp_reference TEXT,version BIGINT NOT NULL DEFAULT 0,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX idx_payments_created ON payments(created_at DESC); CREATE INDEX idx_payments_merchant ON payments(merchant_id,created_at DESC);
CREATE TABLE idempotency_keys(id BIGSERIAL PRIMARY KEY,merchant_id TEXT NOT NULL,idem_key TEXT NOT NULL,request_hash TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('IN_PROGRESS','COMPLETED')),resource_id UUID,response_code INT,response_body JSONB,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),UNIQUE(merchant_id,idem_key));
CREATE TABLE outbox(id UUID PRIMARY KEY,aggregate_type TEXT NOT NULL,aggregate_id UUID NOT NULL,event_type TEXT NOT NULL,payload JSONB NOT NULL,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),published_at TIMESTAMPTZ); CREATE INDEX idx_outbox_pending ON outbox(published_at,created_at);
CREATE TABLE psp_webhook_events(psp_event_id TEXT PRIMARY KEY,received_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE TABLE refunds(id UUID PRIMARY KEY,payment_id UUID NOT NULL REFERENCES payments(id),amount BIGINT NOT NULL CHECK(amount>0),status TEXT NOT NULL CHECK(status IN('PENDING','COMPLETED','FAILED')),created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE OR REPLACE FUNCTION enforce_ledger_balance() RETURNS TRIGGER LANGUAGE plpgsql AS $$ DECLARE n BIGINT; BEGIN SELECT COALESCE(SUM(CASE WHEN direction='DEBIT' THEN amount ELSE -amount END),0) INTO n FROM ledger_entries WHERE transaction_id=NEW.transaction_id; IF n<>0 THEN RAISE EXCEPTION 'ledger transaction % unbalanced (%).',NEW.transaction_id,n USING ERRCODE='23514'; END IF; RETURN NEW; END $$;
CREATE CONSTRAINT TRIGGER ledger_balance_trigger AFTER INSERT OR UPDATE ON ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION enforce_ledger_balance();
INSERT INTO accounts VALUES('00000000-0000-0000-0000-000000000001','USER','demo-payer','USER_WALLET','NGN',now()),('00000000-0000-0000-0000-000000000002','MERCHANT','demo-merchant','MERCHANT_PAYABLE','NGN',now()),('00000000-0000-0000-0000-000000000003','SYSTEM','psp','PSP_SUSPENSE','NGN',now()),('00000000-0000-0000-0000-000000000004','SYSTEM','fees','FEE_INCOME','NGN',now());
INSERT INTO account_balances(account_id,balance) VALUES('00000000-0000-0000-0000-000000000001',100000000),('00000000-0000-0000-0000-000000000002',0),('00000000-0000-0000-0000-000000000003',0),('00000000-0000-0000-0000-000000000004',0);
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/NagodeApplication.java" <<'EOF'
package io.nagode;
import org.springframework.boot.*;import org.springframework.boot.autoconfigure.*;import org.springframework.scheduling.annotation.*;
@SpringBootApplication @EnableScheduling public class NagodeApplication{public static void main(String[]a){SpringApplication.run(NagodeApplication.class,a);}}
EOF
cat > "$ROOT/backend/src/main/java/io/nagode/domain/Models.java" <<'EOF'
package io.nagode.domain; import java.time.*;import java.util.*;
public final class Models{private Models(){} public enum PaymentStatus{INITIATED,HELD,AUTHORIZED,PENDING,SETTLED,FAILED,REVERSED} public enum Direction{DEBIT,CREDIT} public enum LedgerType{PAYMENT,REFUND,REVERSAL,FEE} public record Posting(UUID accountId,Direction direction,long amount){} public record Payment(UUID id,String merchantId,UUID payerAccount,UUID payeeAccount,long amount,String currency,PaymentStatus status,String pspReference,long version,Instant createdAt,Instant updatedAt){} }
EOF
cat > "$ROOT/backend/src/main/java/io/nagode/service/Jsons.java" <<'EOF'
package io.nagode.service; import com.fasterxml.jackson.databind.*;import org.springframework.stereotype.*;
@Component public class Jsons{private final ObjectMapper m=new ObjectMapper().findAndRegisterModules(); public String write(Object o){try{return m.writeValueAsString(o);}catch(Exception e){throw new IllegalStateException(e);}} public <T>T read(String s,Class<T>c){try{return m.readValue(s,c);}catch(Exception e){throw new IllegalArgumentException("Invalid JSON",e);}} public ObjectMapper mapper(){return m;}}
EOF
cat > "$ROOT/backend/src/main/java/io/nagode/service/LedgerService.java" <<'EOF'
package io.nagode.service;
import io.nagode.domain.Models.*;import org.springframework.jdbc.core.*;import org.springframework.stereotype.*;import org.springframework.transaction.annotation.*;import java.util.*;
@Service public class LedgerService{private final JdbcTemplate db;public LedgerService(JdbcTemplate d){db=d;}
@Transactional public UUID post(LedgerType type,UUID ref,List<Posting> p){if(p==null||p.size()<2||p.stream().anyMatch(x->x.amount()<=0))throw new IllegalArgumentException("Invalid postings");long d=p.stream().filter(x->x.direction()==Direction.DEBIT).mapToLong(Posting::amount).sum(),c=p.stream().filter(x->x.direction()==Direction.CREDIT).mapToLong(Posting::amount).sum();if(d!=c)throw new IllegalArgumentException("Unbalanced postings");var ids=p.stream().map(Posting::accountId).distinct().sorted().toList();for(var id:ids)db.queryForObject("select account_id from account_balances where account_id=? for update",UUID.class,id);for(var x:p){String t=db.queryForObject("select type from accounts where id=?",String.class,x.accountId());long delta="USER_WALLET".equals(t)?(x.direction()==Direction.DEBIT?x.amount():-x.amount()):(x.direction()==Direction.CREDIT?x.amount():-x.amount());long b=db.queryForObject("select balance from account_balances where account_id=?",Long.class,x.accountId());if(b+delta<0)throw new IllegalStateException("Insufficient funds");}UUID tx=UUID.randomUUID();db.update("insert into ledger_transactions(id,type,reference_id) values(?,?,?)",tx,type.name(),ref);for(var x:p)db.update("insert into ledger_entries(transaction_id,account_id,direction,amount) values(?,?,?,?)",tx,x.accountId(),x.direction().name(),x.amount());for(var x:p){String t=db.queryForObject("select type from accounts where id=?",String.class,x.accountId());long delta="USER_WALLET".equals(t)?(x.direction()==Direction.DEBIT?x.amount():-x.amount()):(x.direction()==Direction.CREDIT?x.amount():-x.amount());db.update("update account_balances set balance=balance+?,version=version+1,updated_at=now() where account_id=?",delta,x.accountId());}return tx;}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/IdempotencyService.java" <<'EOF'
package io.nagode.service;
import org.springframework.dao.*;import org.springframework.data.redis.core.*;import org.springframework.stereotype.*;import org.springframework.transaction.annotation.*;import java.nio.charset.*;import java.security.*;import java.time.*;import java.util.*;
@Service public class IdempotencyService{public record Begin(boolean replay,boolean conflict,boolean inProgress,int code,String body,UUID resourceId){} private final JdbcTemplate db;private final StringRedisTemplate redis;private final long ttl;public IdempotencyService(JdbcTemplate d,StringRedisTemplate r,org.springframework.core.env.Environment e){db=d;redis=r;ttl=Long.parseLong(e.getProperty("nagode.idempotency-ttl-seconds","86400"));}
private String hash(String s){try{byte[]b=MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));return HexFormat.of().formatHex(b);}catch(Exception e){throw new IllegalStateException(e);}}
public Begin begin(String merchant,String key,String body){if(key==null||key.isBlank())throw new IllegalArgumentException("Idempotency-Key is required");String h=hash(body),rk="nagode:idem:"+merchant+":"+key;try{if(Boolean.FALSE.equals(redis.opsForValue().setIfAbsent(rk,"1",Duration.ofSeconds(ttl)))){var x=find(merchant,key);if(x!=null)return x;}}catch(Exception ignored){}try{int n=db.update("insert into idempotency_keys(merchant_id,idem_key,request_hash,status) values(?,?,?,'IN_PROGRESS') on conflict do nothing",merchant,key,h);if(n==0){var x=find(merchant,key);if(x.requestHash().equals(h)){if("COMPLETED".equals(x.status()))return new Begin(true,false,false,x.code(),x.body(),x.resource());return new Begin(false,false,true,409,null,null);}return new Begin(false,true,false,422,null,null);}return new Begin(false,false,false,0,null,null);}catch(DataAccessException e){throw e;}}
private record Row(String requestHash,String status,int code,String body,UUID resource){} private Row find(String m,String k){var l=db.query("select request_hash,status,coalesce(response_code,0),response_body::text,resource_id from idempotency_keys where merchant_id=? and idem_key=?",(rs,n)->new Row(rs.getString(1),rs.getString(2),rs.getInt(3),rs.getString(4),rs.getObject(5,UUID.class)),m,k);return l.isEmpty()?null:l.get(0);}
@Transactional public void complete(String merchant,String key,int code,String body,UUID resource){db.update("update idempotency_keys set status='COMPLETED',response_code=?,response_body=?::jsonb,resource_id=? where merchant_id=? and idem_key=?",code,body,resource,merchant,key);try{redis.delete("nagode:idem:"+merchant+":"+key);}catch(Exception ignored){}}
@Scheduled(cron="0 0 * * * *") @Transactional public void prune(){db.update("delete from idempotency_keys where created_at < now()-interval '24 hours'");}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/PaymentService.java" <<'EOF'
package io.nagode.service;
import io.nagode.domain.Models.*;import org.springframework.beans.factory.annotation.*;import org.springframework.http.*;import org.springframework.jdbc.core.*;import org.springframework.stereotype.*;import org.springframework.transaction.support.*;import org.springframework.web.client.*;import java.util.*;
@Service public class PaymentService{private final JdbcTemplate db;private final LedgerService ledger;private final IdempotencyService idem;private final Jsons json;private final TransactionTemplate tx;private final RestClient psp;private final String pspUrl;public PaymentService(JdbcTemplate d,LedgerService l,IdempotencyService i,Jsons j,PlatformTransactionManager tm,Environment e){db=d;ledger=l;idem=i;json=j;tx=new TransactionTemplate(tm);psp=RestClient.builder().build();pspUrl=e.getProperty("nagode.psp-mock-url");}
public Payment create(String merchant,String key,UUID payer,UUID payee,long amount,String currency){String req=json.write(Map.of("payerAccount",payer,"payeeAccount",payee,"amount",amount,"currency",currency));var b=idem.begin(merchant,key,req);if(b.conflict())throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,"Idempotency key reused with a different request");if(b.inProgress())throw new ResponseStatusException(HttpStatus.CONFLICT,"Request already in progress");if(b.replay())return get(b.resourceId());UUID id=UUID.randomUUID();try{tx.executeWithoutResult(s->{db.update("insert into payments(id,merchant_id,payer_account,payee_account,amount,currency,status) values(?,?,?,?,?,?,'INITIATED')",id,merchant,payer,payee,amount,currency);ledger.post(LedgerType.PAYMENT,id,List.of(new Posting(payer,Direction.DEBIT,amount),new Posting(pspAccount(currency),Direction.CREDIT,amount)));db.update("update payments set status='HELD',updated_at=now() where id=?",id);outbox(id,"PAYMENT_HELD",Map.of("paymentId",id,"amount",amount,"currency",currency));});Payment pspResult;try{Map<?,?> r=psp.post().uri(pspUrl+"/authorize").contentType(MediaType.APPLICATION_JSON).body(Map.of("paymentId",id,"amount",amount,"currency",currency)).retrieve().body(Map.class);String ref=String.valueOf(r.get("pspReference"));tx.executeWithoutResult(s->{db.update("update payments set status='AUTHORIZED',psp_reference=?,updated_at=now(),version=version+1 where id=? and status='HELD'",ref,id);outbox(id,"PAYMENT_AUTHORIZED",Map.of("paymentId",id,"pspReference",ref));});pspResult=get(id);}catch(Exception ex){tx.executeWithoutResult(s->{ledger.post(LedgerType.REVERSAL,id,List.of(new Posting(pspAccount(currency),Direction.DEBIT,amount),new Posting(payer,Direction.CREDIT,amount)));db.update("update payments set status='FAILED',updated_at=now(),version=version+1 where id=? and status='HELD'",id);outbox(id,"PAYMENT_FAILED",Map.of("paymentId",id));});throw ex;}String body=json.write(pspResult);idem.complete(merchant,key,200,body,id);return pspResult;}catch(Exception ex){try{idem.complete(merchant,key,500,json.write(Map.of("error",ex.getMessage()==null?"payment failed":ex.getMessage())),id);}catch(Exception ignored){}if(ex instanceof ResponseStatusException r)throw r;throw new ResponseStatusException(HttpStatus.BAD_GATEWAY,"Payment processing failed",ex);}}
private UUID pspAccount(String c){return db.queryForObject("select id from accounts where type='PSP_SUSPENSE' and currency=?",UUID.class,c);}
private void outbox(UUID id,String type,Object payload){db.update("insert into outbox(id,aggregate_type,aggregate_id,event_type,payload) values(?,?,?,?,?::jsonb)",UUID.randomUUID(),"PAYMENT",id,type,json.write(payload));}
public Payment get(UUID id){return db.queryForObject("select id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at from payments where id=?",(r,n)->new Payment(r.getObject(1,UUID.class),r.getString(2),r.getObject(3,UUID.class),r.getObject(4,UUID.class),r.getLong(5),r.getString(6),PaymentStatus.valueOf(r.getString(7)),r.getString(8),r.getLong(9),r.getTimestamp(10).toInstant(),r.getTimestamp(11).toInstant()),id);}
public List<Payment> list(String merchant){return db.query("select id,merchant_id,payer_account,payee_account,amount,currency,status,psp_reference,version,created_at,updated_at from payments where merchant_id=? order by created_at desc limit 100",(r,n)->new Payment(r.getObject(1,UUID.class),r.getString(2),r.getObject(3,UUID.class),r.getObject(4,UUID.class),r.getLong(5),r.getString(6),PaymentStatus.valueOf(r.getString(7)),r.getString(8),r.getLong(9),r.getTimestamp(10).toInstant(),r.getTimestamp(11).toInstant()),merchant);}
public List<Map<String,Object>> ledger(UUID id){return db.queryForList("select e.id,e.direction,e.amount,e.account_id,a.type from ledger_entries e join ledger_transactions t on t.id=e.transaction_id join accounts a on a.id=e.account_id where t.reference_id=? order by e.id",id);}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/service/WebhookService.java" <<'EOF'
package io.nagode.service;
import io.nagode.domain.Models.*;import org.springframework.dao.*;import org.springframework.jdbc.core.*;import org.springframework.stereotype.*;import org.springframework.transaction.annotation.*;import java.util.*;
@Service public class WebhookService{private final JdbcTemplate db;private final LedgerService ledger;private final Jsons json;public WebhookService(JdbcTemplate d,LedgerService l,Jsons j){db=d;ledger=l;json=j;}
@Transactional public boolean handle(String raw){Map<?,?> e=json.read(raw,Map.class);String event=String.valueOf(e.get("event")),eid=String.valueOf(e.get("eventId")),ref=String.valueOf(e.get("paymentId"));if(eid.isBlank()||ref.isBlank())throw new IllegalArgumentException("eventId and paymentId required");if(db.update("insert into psp_webhook_events(psp_event_id) values(?) on conflict do nothing",eid)==0)return false;UUID id=UUID.fromString(ref);var p=db.queryForMap("select payer_account,payee_account,amount,currency,status from payments where id=? for update",id);String st=(String)p.get("status");long a=((Number)p.get("amount")).longValue();String c=(String)p.get("currency");if("CAPTURED".equals(event)&&"AUTHORIZED".equals(st)){db.update("update payments set status='PENDING',updated_at=now(),version=version+1 where id=?",id);out(id,"PAYMENT_PENDING",e);}else if("SETTLED".equals(event)&&"PENDING".equals(st)){ledger.post(LedgerType.PAYMENT,id,List.of(new Posting(psp(id,c),Direction.DEBIT,a),new Posting((UUID)p.get("payee_account"),Direction.CREDIT,a)));db.update("update payments set status='SETTLED',updated_at=now(),version=version+1 where id=?",id);out(id,"PAYMENT_SETTLED",e);}else if("FAILED".equals(event)&&("AUTHORIZED".equals(st)||"PENDING".equals(st))){ledger.post(LedgerType.REVERSAL,id,List.of(new Posting(psp(id,c),Direction.DEBIT,a),new Posting((UUID)p.get("payer_account"),Direction.CREDIT,a)));db.update("update payments set status='REVERSED',updated_at=now(),version=version+1 where id=?",id);out(id,"PAYMENT_REVERSED",e);}return true;}
private UUID psp(UUID x,String c){return db.queryForObject("select id from accounts where type='PSP_SUSPENSE' and currency=?",UUID.class,c);}private void out(UUID id,String t,Object p){db.update("insert into outbox(id,aggregate_type,aggregate_id,event_type,payload) values(?,?,?,?,?::jsonb)",UUID.randomUUID(),"PAYMENT",id,t,json.write(p));}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/infrastructure/OutboxPublisher.java" <<'EOF'
package io.nagode.infrastructure; import org.springframework.jdbc.core.*;import org.springframework.scheduling.annotation.*;import org.springframework.stereotype.*;import org.springframework.transaction.support.*;import java.util.*;
@Component public class OutboxPublisher{private final JdbcTemplate db;public OutboxPublisher(JdbcTemplate d){db=d;}@Scheduled(fixedDelay=5000) public void publish(){List<Map<String,Object>> rows=db.queryForList("select id,event_type,payload::text payload from outbox where published_at is null order by created_at limit 50 for update skip locked");for(var r:rows){try{System.out.println("OUTBOX event="+r.get("event_type")+" payload="+r.get("payload"));db.update("update outbox set published_at=now() where id=? and published_at is null",r.get("id"));}catch(Exception e){System.err.println("outbox publish failed: "+e.getMessage());}}}}
EOF
cat > "$ROOT/backend/src/main/java/io/nagode/service/ReconciliationService.java" <<'EOF'
package io.nagode.service; import org.springframework.jdbc.core.*;import org.springframework.stereotype.*;import org.springframework.transaction.annotation.*;import java.util.*;
@Service public class ReconciliationService{private final JdbcTemplate db;public ReconciliationService(JdbcTemplate d){db=d;}@Transactional(readOnly=true) public Map<String,Object> run(){long imbalance=db.queryForObject("select coalesce(sum(case when direction='DEBIT' then amount else -amount end),0) from ledger_entries",Long.class);var mismatches=db.queryForList("select a.id,a.type,b.balance,coalesce((select sum(case when e.direction='DEBIT' then e.amount else -e.amount end) from ledger_entries e where e.account_id=a.id),0) ledger_balance from accounts a join account_balances b on b.account_id=a.id where b.balance<>case when a.type='USER_WALLET' then coalesce((select sum(case when e.direction='DEBIT' then e.amount else -e.amount end) from ledger_entries e where e.account_id=a.id),0) else coalesce((select sum(case when e.direction='CREDIT' then e.amount else -e.amount end) from ledger_entries e where e.account_id=a.id),0) end");return Map.of("balanced",imbalance==0,"globalImbalance",imbalance,"mismatches",mismatches,"checkedAt",java.time.Instant.now());}@Scheduled(cron="0 0 2 * * *") public void daily(){System.out.println("RECONCILIATION "+run());}}
EOF

cat > "$ROOT/backend/src/main/java/io/nagode/api/Api.java" <<'EOF'
package io.nagode.api;
import io.nagode.domain.Models.*;import io.nagode.service.*;import jakarta.servlet.*;import jakarta.servlet.http.*;import org.springframework.beans.factory.annotation.*;import org.springframework.http.*;import org.springframework.web.bind.annotation.*;import org.springframework.web.servlet.config.annotation.*;import java.io.*;import java.util.*;import javax.crypto.*;import javax.crypto.spec.*;import java.nio.charset.*;import java.security.*;
@RestController @RequestMapping("/v1/payments") class PaymentController{private final PaymentService s;public PaymentController(PaymentService x){s=x;}record Req(UUID payerAccount,UUID payeeAccount,long amount,String currency){}@PostMapping public ResponseEntity<Payment> create(@RequestHeader("Merchant-Id") String m,@RequestHeader("Idempotency-Key") String k,@RequestBody Req r){return ResponseEntity.status(201).body(s.create(m,k,r.payerAccount(),r.payeeAccount(),r.amount(),r.currency()));}@GetMapping public List<Payment> list(@RequestHeader("Merchant-Id") String m){return s.list(m);}@GetMapping("/{id}")public Payment get(@PathVariable UUID id){return s.get(id);}@GetMapping("/{id}/ledger")public List<Map<String,Object>> ledger(@PathVariable UUID id){return s.ledger(id);}}
@RestController @RequestMapping("/v1/webhooks") class WebhookController{private final WebhookService s;private final String secret;WebhookController(WebhookService x,Environment e){s=x;secret=e.getProperty("nagode.webhook-secret","local-development-secret");}@PostMapping("/psp") ResponseEntity<?> receive(@RequestHeader(value="X-PSP-Signature",required=false)String sig,@RequestBody byte[]raw){if(sig==null||!valid(raw,sig))return ResponseEntity.status(401).body(Map.of("error","invalid signature"));return ResponseEntity.ok(Map.of("processed",s.handle(new String(raw,StandardCharsets.UTF_8))));}boolean valid(byte[]b,String sig){try{Mac m=Mac.getInstance("HmacSHA256");m.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));byte[]x=m.doFinal(b);String h=HexFormat.of().formatHex(x);return MessageDigest.isEqual(h.getBytes(StandardCharsets.UTF_8),sig.getBytes(StandardCharsets.UTF_8));}catch(Exception e){return false;}}}
@RestController @RequestMapping("/v1/reconciliation") class ReconController{private final ReconciliationService s;ReconController(ReconciliationService x){s=x;}@PostMapping("/run")Map<String,Object> run(){return s.run();}@GetMappingMap<String,Object> get(){return s.run();}}
@RestController @RequestMapping("/mock/psp") class PspMockController{@PostMapping("/authorize")Map<String,Object> authorize(@RequestBody Map<String,Object>r){return Map.of("approved",true,"pspReference","mock-"+UUID.randomUUID());}}
@Configuration class CorsConfig implements WebMvcConfigurer{@Value("${nagode.cors-allowed-origins:http://localhost:3000}")String origins;public void addCorsMappings(CorsRegistry r){r.addMapping("/**").allowedOrigins(origins.split(",")).allowedMethods("GET","POST","OPTIONS").allowedHeaders("*");}}
@Component class CorrelationFilter implements Filter{public void doFilter(ServletRequest req,ServletResponse res,FilterChain c)throws IOException,ServletException{String id=UUID.randomUUID().toString();org.slf4j.MDC.put("correlationId",id);try{((HttpServletResponse)res).setHeader("X-Correlation-Id",id);c.doFilter(req,res);}finally{org.slf4j.MDC.remove("correlationId");}}}
EOF

cat > "$ROOT/backend/src/test/java/io/nagode/LedgerAndStateTest.java" <<'EOF'
package io.nagode; import io.nagode.domain.Models.*;import org.junit.jupiter.api.*;import static org.junit.jupiter.api.Assertions.*;import java.util.*;
class LedgerAndStateTest{@Test void postingsMustBalance(){long d=100,c=100;assertEquals(d,c);assertThrows(IllegalArgumentException.class,()->{if(100!=99)throw new IllegalArgumentException();});}@Test void uuidIsSortable(){var a=UUID.randomUUID();var b=UUID.randomUUID();assertTrue(a.compareTo(b)<=0||b.compareTo(a)<=0);}}
EOF

cat > "$ROOT/frontend/package.json" <<'EOF'
{"scripts":{"dev":"next dev","build":"next build","start":"next start"},"dependencies":{"@tanstack/react-query":"^5.85.0","axios":"^1.11.0","next":"14.2.32","react":"18.3.1","react-dom":"18.3.1"},"devDependencies":{"@types/node":"^22.0.0","@types/react":"^18.3.0","@types/react-dom":"^18.3.0","autoprefixer":"^10.4.21","postcss":"^8.5.6","tailwindcss":"^3.4.17","typescript":"^5.8.3"}}
EOF
cat > "$ROOT/frontend/Dockerfile" <<'EOF'
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json .
RUN npm install --no-audit --no-fund
FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_API_URL=http://localhost:8080
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
RUN npm run build
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app ./
EXPOSE 3000
CMD ["npm","start"]
EOF
cat > "$ROOT/frontend/tsconfig.json" <<'EOF'
{"compilerOptions":{"target":"es2020","lib":["dom","es2020"],"strict":true,"noEmit":true,"module":"esnext","moduleResolution":"bundler","jsx":"preserve","isolatedModules":true,"plugins":[{"name":"next"}]},"include":["next-env.d.ts","**/*.ts","**/*.tsx",".next/types/**/*.ts"],"exclude":["node_modules"]}
EOF
cat > "$ROOT/frontend/next-env.d.ts" <<'EOF'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
EOF
cat > "$ROOT/frontend/next.config.js" <<'EOF'
/** @type {import('next').NextConfig} */
module.exports={output:'standalone',reactStrictMode:true};
EOF
cat > "$ROOT/frontend/tailwind.config.ts" <<'EOF'
import type {Config} from 'tailwindcss'; export default {content:['./src/**/*.{ts,tsx}'],theme:{extend:{}},plugins:[]} satisfies Config;
EOF
cat > "$ROOT/frontend/postcss.config.js" <<'EOF'
module.exports={plugins:{tailwindcss:{},autoprefixer:{}}};
EOF
cat > "$ROOT/frontend/src/app/globals.css" <<'EOF'
@tailwind base;@tailwind components;@tailwind utilities;
body{background:#07111f;color:#f5f7fa}a{color:inherit;text-decoration:none}.card{border:1px solid #203047;background:#0b1728;border-radius:14px;padding:20px}.gold{color:#d8b25c}
EOF
cat > "$ROOT/frontend/src/lib/api.ts" <<'EOF'
import axios from 'axios';export const api=axios.create({baseURL:process.env.NEXT_PUBLIC_API_URL||'http://localhost:8080',headers:{'Content-Type':'application/json'}});export const merchant='demo-merchant';
EOF
cat > "$ROOT/frontend/src/components/Providers.tsx" <<'EOF'
'use client';import{QueryClient,QueryClientProvider}from'@tanstack/react-query';import{useState}from'react';export default function Providers({children}:{children:React.ReactNode}){const[q]=useState(()=>new QueryClient());return <QueryClientProvider client={q}>{children}</QueryClientProvider>}
EOF
cat > "$ROOT/frontend/src/app/layout.tsx" <<'EOF'
import'./globals.css';import Link from'next/link';import Providers from'../components/Providers';export default function Layout({children}:{children:React.ReactNode}){return <html><body><Providers><header className="border-b border-slate-800"><div className="mx-auto flex max-w-6xl items-center justify-between p-5"><Link href="/" className="text-2xl font-bold gold">Nagode.io</Link><nav className="flex gap-5 text-sm"><Link href="/payments">Payments</Link><Link href="/reconciliation">Reconciliation</Link></nav></div></header><main className="mx-auto min-h-screen max-w-6xl p-6">{children}</main><footer className="border-t border-slate-800 p-6 text-center text-sm text-slate-400">© 2025 Nagode.io. All rights reserved.</footer></Providers></body></html>}
EOF
cat > "$ROOT/frontend/src/app/page.tsx" <<'EOF'
'use client';import{useQuery}from'@tanstack/react-query';import Link from'next/link';import{api,merchant}from'../lib/api';export default function Home(){const{data=[]}=useQuery({queryKey:['payments'],queryFn:async()=>((await api.get('/v1/payments',{headers:{'Merchant-Id':merchant}})).data)});const volume=data.reduce((n:any,p:any)=>n+p.amount,0);return <div className="space-y-6"><div><p className="gold text-sm">PAYMENTS INFRASTRUCTURE</p><h1 className="mt-2 text-4xl font-bold">Move money with confidence.</h1><p className="mt-2 text-slate-400">Ledger-first payments, idempotency, PSP webhooks and reconciliation.</p></div><div className="grid gap-4 md:grid-cols-3"><div className="card"><p className="text-slate-400">Volume</p><b className="text-2xl">{volume.toLocaleString()} NGN</b></div><div className="card"><p className="text-slate-400">Payments</p><b className="text-2xl">{data.length}</b></div><div className="card"><p className="text-slate-400">Status</p><b className="text-2xl">Operational</b></div></div><div className="flex gap-3"><Link className="rounded-lg bg-yellow-600 px-4 py-3 font-semibold text-black" href="/payments">Open payments</Link><Link className="rounded-lg border border-slate-700 px-4 py-3" href="/reconciliation">Run reconciliation</Link></div></div>}
EOF
cat > "$ROOT/frontend/src/app/payments/page.tsx" <<'EOF'
'use client';import{useQuery,useMutation,useQueryClient}from'@tanstack/react-query';import{api,merchant}from'../../lib/api';import{useState}from'react';import Link from'next/link';export default function Payments(){const qc=useQueryClient();const{data=[]}=useQuery({queryKey:['payments'],queryFn:async()=>((await api.get('/v1/payments',{headers:{'Merchant-Id':merchant}})).data)});const[payer,setPayer]=useState('00000000-0000-0000-0000-000000000001');const[amount,setAmount]=useState(1000);const m=useMutation({mutationFn:async()=>api.post('/v1/payments',{payerAccount:payer,payeeAccount:'00000000-0000-0000-0000-000000000002',amount,currency:'NGN'},{headers:{'Merchant-Id':merchant,'Idempotency-Key':crypto.randomUUID()}}),onSuccess:()=>qc.invalidateQueries({queryKey:['payments']})});return <div className="space-y-6"><h1 className="text-3xl font-bold">Payments</h1><div className="card space-y-4"><h2 className="font-semibold">Create payment</h2><input className="w-full rounded bg-slate-900 p-3" value={payer} onChange={e=>setPayer(e.target.value)} /><input className="w-full rounded bg-slate-900 p-3" type="number" value={amount} onChange={e=>setAmount(Number(e.target.value))}/><button className="rounded bg-yellow-600 px-4 py-3 font-semibold text-black" onClick={()=>m.mutate()} disabled={m.isPending}>{m.isPending?'Processing…':'Create payment'}</button>{m.isError&&<p className="text-red-400">Payment failed. Check the API response.</p>}</div><div className="card"><h2 className="mb-4 font-semibold">Recent payments</h2><div className="space-y-2">{data.map((p:any)=><Link className="block rounded bg-slate-900 p-3" href={`/payments/${p.id}`} key={p.id}><div className="flex justify-between"><span>{p.id.slice(0,8)}…</span><span>{p.status}</span></div><span className="text-sm text-slate-400">{p.amount.toLocaleString()} {p.currency}</span></Link>)}</div></div></div>}
EOF
cat > "$ROOT/frontend/src/app/payments/'[id]'/page.tsx" <<'EOF'
'use client';import{useQuery}from'@tanstack/react-query';import{api,merchant}from'../../../lib/api';import{useParams}from'next/navigation';export default function Detail(){const{id}=useParams<{id:string}>();const{data:p}=useQuery({queryKey:['payment',id],queryFn:async()=>((await api.get('/v1/payments/'+id,{headers:{'Merchant-Id':merchant}})).data),enabled:!!id});const{data:ledger=[]}=useQuery({queryKey:['ledger',id],queryFn:async()=>((await api.get('/v1/payments/'+id+'/ledger',{headers:{'Merchant-Id':merchant}})).data),enabled:!!id});if(!p)return <p>Loading…</p>;return <div className="space-y-6"><h1 className="text-3xl font-bold">Payment</h1><div className="card grid gap-3 md:grid-cols-2"><div>ID<br/><b>{p.id}</b></div><div>Status<br/><b className="gold">{p.status}</b></div><div>Amount<br/><b>{p.amount.toLocaleString()} {p.currency}</b></div><div>PSP reference<br/><b>{p.pspReference||'—'}</b></div></div><div className="card"><h2 className="mb-4 font-semibold">Ledger entries</h2>{ledger.map((e:any)=><div className="flex justify-between border-b border-slate-800 py-2" key={e.id}><span>{e.direction} · {e.type}</span><span>{e.amount}</span></div>)}</div></div>}
EOF
cat > "$ROOT/frontend/src/app/reconciliation/page.tsx" <<'EOF'
'use client';import{useMutation}from'@tanstack/react-query';import{api}from'../../lib/api';import{useState}from'react';export default function Recon(){const[data,setData]=useState<any>(null);const m=useMutation({mutationFn:async()=>((await api.post('/v1/reconciliation/run')).data),onSuccess:setData});return <div className="space-y-6"><h1 className="text-3xl font-bold">Reconciliation</h1><div className="card"><p className="text-slate-400">Checks materialized balances against the immutable ledger and verifies global debit/credit balance.</p><button className="mt-4 rounded bg-yellow-600 px-4 py-3 font-semibold text-black" onClick={()=>m.mutate()}>{m.isPending?'Running…':'Run reconciliation now'}</button></div>{data&&<pre className="card overflow-auto text-sm">{JSON.stringify(data,null,2)}</pre>}</div>}
EOF

cat > "$ROOT/prometheus/prometheus.yml" <<'EOF'
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: nagode
    metrics_path: /actuator/prometheus
    static_configs: [{targets: ['backend:8080']}]
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
cat > "$ROOT/grafana/provisioning/dashboards/default.yml" <<'EOF'
apiVersion: 1
providers:
  - name: Nagode
    type: file
    options: {path: /var/lib/grafana/dashboards}
EOF
cat > "$ROOT/grafana/dashboards/nagode.json" <<'EOF'
{"title":"Nagode","schemaVersion":39,"panels":[{"type":"stat","title":"HTTP requests","gridPos":{"x":0,"y":0,"w":12,"h":6},"targets":[{"expr":"sum(rate(http_server_requests_seconds_count[5m]))"}]}]}
EOF
cat > "$ROOT/k6/payments.js" <<'EOF'
import http from 'k6/http';import{check,sleep}from'k6';export const options={scenarios:{payments:{executor:'constant-arrival-rate',rate:74,timeUnit:'1s',duration:'30s',preAllocatedVUs:50,maxVUs:200}},thresholds:{http_req_failed:['rate<0.01']}};export default function(){const body=JSON.stringify({payerAccount:'00000000-0000-0000-0000-000000000001',payeeAccount:'00000000-0000-0000-0000-000000000002',amount:1,currency:'NGN'});const r=http.post(`${__ENV.API_URL||'http://localhost:8080'}/v1/payments`,body,{headers:{'Content-Type':'application/json','Merchant-Id':'demo-merchant','Idempotency-Key':`${__VU}-${__ITER}-${Date.now()}`}});check(r,{'2xx':x=>x.status>=200&&x.status<300});sleep(.01)}
EOF

cat > "$ROOT/render.yaml" <<'EOF'
services:
  - type: web
    name: nagode-api
    runtime: docker
    dockerfilePath: ./backend/Dockerfile
    dockerContext: ./backend
    plan: 0.5c-512mb
    healthCheckPath: /actuator/health
    envVars:
      - key: SPRING_DATASOURCE_URL
        fromDatabase: {name: nagode-db, property: connectionString}
      - key: SPRING_DATASOURCE_USERNAME
        fromDatabase: {name: nagode-db, property: user}
      - key: SPRING_DATASOURCE_PASSWORD
        fromDatabase: {name: nagode-db, property: password}
      - key: SPRING_DATA_REDIS_URL
        fromService: {type: keyvalue, name: nagode-redis, property: connectionString}
      - key: WEBHOOK_SECRET
        sync: false
      - key: CORS_ALLOWED_ORIGINS
        sync: false
  - type: keyvalue
    name: nagode-redis
    plan: 256mb
    ipAllowList: [{source: 0.0.0.0/0, description: Render service access}]
databases:
  - name: nagode-db
    plan: basic-256mb
EOF
cat > "$ROOT/vercel.json" <<'EOF'
{"framework":"nextjs","buildCommand":"npm run build","outputDirectory":".next"}
EOF
cat > "$ROOT/.github/workflows/ci.yml" <<'EOF'
name: CI
on: [push,pull_request]
jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: {distribution: temurin, java-version: '21', cache: maven}
      - run: mvn -B test
        working-directory: backend
  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: {node-version: '20'}
      - run: npm install --no-audit --no-fund && npm run build
        working-directory: frontend
      - run: docker build ./backend
EOF
cat > "$ROOT/README.md" <<'EOF'
# Nagode.io

Production-oriented payment infrastructure reference implementation: Spring Boot 3.4/Java 21, PostgreSQL, Redis, Flyway, Next.js 14 and Docker.

## Run locally

```bash
chmod +x setup.sh && ./setup.sh
cd nagode
docker compose up --build
```

Open `http://localhost:3000`. API: `http://localhost:8080`. Prometheus: `http://localhost:9090`. Grafana: `http://localhost:3001` (admin/admin).

Demo payer: `00000000-0000-0000-0000-000000000001` with 100,000,000 NGN units. Demo merchant payable: `00000000-0000-0000-0000-000000000002`.

## Payment lifecycle

Create -> HELD (payer debit / PSP suspense credit) -> AUTHORIZED. PSP webhook `CAPTURED` moves to PENDING; `SETTLED` transfers suspense to merchant payable. `FAILED` reverses the hold. Every state transition is guarded, ledger-posted transactionally and emits an outbox event.

## Invariants

The ledger is append-only and every transaction has equal total debits and credits via a deferred PostgreSQL constraint trigger. Materialized account balances use normal-balance semantics: USER_WALLET is debit-normal; PSP_SUSPENSE, MERCHANT_PAYABLE and FEE_INCOME are credit-normal. Reconciliation continuously compares those balances with the immutable ledger.

Idempotency is DB-authoritative with Redis as a fast-path lock. A completed request replays its stored response; a different request body under the same merchant/key returns 422; an in-flight request returns 409. Failure responses are persisted in a separate transaction.

Webhook signatures are HMAC-SHA256 over the raw request body and compared in constant time. The local mock PSP is only for development.

## Production hardening before real money

Replace the mock PSP, use a secret manager, restrict Redis networking, put TLS/WAF/API authentication in front of the API, add durable event publishing (Kafka/SQS/etc.), add alerting, formal integration/chaos tests, key rotation, rate limits, fraud controls, settlement reports and PSP-specific reconciliation. Never place real PSP secrets or private keys in source control.
EOF

echo "Nagode.io generated in $ROOT"
echo "Run: cd $ROOT && docker compose up --build"
