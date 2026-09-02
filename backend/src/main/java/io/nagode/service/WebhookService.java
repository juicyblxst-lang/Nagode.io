package io.nagode.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;

@Service
public class WebhookService {
  private final FinancialService financial; private final org.springframework.jdbc.core.JdbcTemplate db; private final ObjectMapper json; private final String secret;
  public WebhookService(FinancialService f,org.springframework.jdbc.core.JdbcTemplate db,ObjectMapper json,Environment env){this.financial=f;this.db=db;this.json=json;this.secret=env.getProperty("nagode.webhook-secret","");}
  @Transactional
  public void handle(String signature,String eventId,String raw){
    if(signature==null||signature.isBlank()||secret.isBlank()||!valid(signature,raw))throw new ResponseStatusException(HttpStatus.UNAUTHORIZED,"invalid webhook signature");
    int n=db.update("insert into psp_webhook_events(psp_event_id) values(?) on conflict do nothing",eventId);if(n==0)return;
    try{JsonNode p=json.readTree(raw);UUID payment=UUID.fromString(p.path("paymentId").asText());String type=p.path("type").asText();switch(type){case "CAPTURED"->financial.capture(payment);case "SETTLED"->financial.settle(payment);case "FAILED"->financial.fail(payment);default->throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"unsupported webhook event");}}catch(ResponseStatusException e){throw e;}catch(Exception e){throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"invalid webhook payload");}
  }
  private boolean valid(String supplied,String raw){try{String s=supplied.startsWith("sha256=")?supplied.substring(7):supplied;Mac mac=Mac.getInstance("HmacSHA256");mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8),"HmacSHA256"));String expected=HexFormat.of().formatHex(mac.doFinal(raw.getBytes(StandardCharsets.UTF_8)));return MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8),s.getBytes(StandardCharsets.UTF_8));}catch(Exception e){return false;}}
}
