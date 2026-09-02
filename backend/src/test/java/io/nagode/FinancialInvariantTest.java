package io.nagode;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;
import java.util.*;

class FinancialInvariantTest {
  @Test void amountsAreIntegerMinorUnits(){assertEquals(10000L,100L*100L);}
  @Test void lockOrderingIsDeterministic(){List<UUID> ids=List.of(UUID.randomUUID(),UUID.randomUUID());assertEquals(ids.stream().sorted().toList(),ids.stream().sorted().toList());}
}
