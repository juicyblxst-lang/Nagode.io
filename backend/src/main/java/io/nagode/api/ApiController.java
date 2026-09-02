package io.nagode.api;

import io.nagode.service.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/v1")
public class ApiController {
  private final FinancialService financial; private final IdempotencyService idem; private final WebhookService webhooks;
  public ApiController(FinancialService financial,IdempotencyService idem,WebhookService webhooks){this.financial=financial;this.idem=idem;this.webhooks=webhooks;}
  public record CreatePayment(@NotNull @Positive Long amount,@NotBlank @Pattern(regexp="[A-Z]{3}") String currency){}
  public record Refund(@NotNull @Positive Long amount){}

  @GetMapping("/wallet") public Object wallet(){return financial.wallet();}
  @GetMapping("/payments") public Object payments(@RequestParam(defaultValue="50") int limit,@RequestParam(defaultValue="0") int offset){return financial.list(Math.min(Math.max(limit,1),100),Math.max(offset,0));}
  @GetMapping("/payments/{id}") public Object payment(@PathVariable UUID id){return Map.of("payment",financial.get(id),"history",financial.history(id),"ledger",financial.ledger(id));}

  @PostMapping("/payments") public ResponseEntity<String> create(@RequestHeader("Idempotency-Key") String key,@RequestBody @Valid CreatePayment req){
    String merchant="demo-merchant"; String body="{\"amount\":"+req.amount()+",\"currency\":\""+req.currency()+"\"}";
    var b=idem.begin(merchant,key,body);if(b.replay()||b.conflict()||b.inProgress())return ResponseEntity.status(b.code()).contentType(MediaType.APPLICATION_JSON).body(b.body());
    try {UUID id=financial.createPayment(merchant,req.amount(),req.currency());String out="{\"id\":\""+id+"\",\"status\":\"HELD\"}";idem.complete(merchant,key,id,201,out);return ResponseEntity.status(201).contentType(MediaType.APPLICATION_JSON).body(out);}
    catch(Exception e){String out="{\"error\":\"PAYMENT_FAILED\",\"message\":\"payment could not be created\"}";idem.fail(merchant,key,500,out);return ResponseEntity.status(500).contentType(MediaType.APPLICATION_JSON).body(out);}
  }

  @PostMapping("/payments/{id}/refund") public ResponseEntity<String> refund(@RequestHeader("Idempotency-Key") String key,@PathVariable UUID id,@RequestBody @Valid Refund req){
    String merchant="demo-merchant";String body="{\"paymentId\":\""+id+"\",\"amount\":"+req.amount()+"}";var b=idem.begin(merchant,key,body);if(b.replay()||b.conflict()||b.inProgress())return ResponseEntity.status(b.code()).contentType(MediaType.APPLICATION_JSON).body(b.body());
    try{UUID refund=financial.refund(id,req.amount());String out="{\"id\":\""+refund+"\",\"status\":\"COMPLETED\"}";idem.complete(merchant,key,refund,201,out);return ResponseEntity.status(201).contentType(MediaType.APPLICATION_JSON).body(out);}catch(IllegalArgumentException|IllegalStateException e){String out="{\"error\":\"REFUND_REJECTED\",\"message\":\"refund is invalid or exceeds the refundable amount\"}";idem.fail(merchant,key,422,out);return ResponseEntity.unprocessableEntity().contentType(MediaType.APPLICATION_JSON).body(out);}catch(Exception e){String out="{\"error\":\"REFUND_FAILED\",\"message\":\"refund could not be completed\"}";idem.fail(merchant,key,500,out);return ResponseEntity.internalServerError().contentType(MediaType.APPLICATION_JSON).body(out);}
  }

  @PostMapping("/webhooks/psp") public ResponseEntity<Map<String,String>> webhook(@RequestHeader(value="X-PSP-Signature",required=false) String signature,@RequestHeader("X-PSP-Event-Id") String eventId,@RequestBody String raw){webhooks.handle(signature,eventId,raw);return ResponseEntity.ok(Map.of("status","accepted"));}
  @PostMapping("/reconciliation/run") public Object reconcile(){return Map.of("status","started","message","reconciliation runs asynchronously on the scheduler");}
  @GetMapping("/reconciliation") public Object reconciliation(){return Map.of("status","available");}
}
