package io.nagode;
import io.nagode.service.PaymentRules;import org.junit.jupiter.api.Test;import static org.junit.jupiter.api.Assertions.*;
class PaymentStateTest{@Test void allowed(){assertTrue(PaymentRules.validTransition("INITIATED","HELD"));assertTrue(PaymentRules.validTransition("PENDING","SETTLED"));}@Test void denied(){assertFalse(PaymentRules.validTransition("SETTLED","HELD"));assertFalse(PaymentRules.validTransition("FAILED","SETTLED"));}}
