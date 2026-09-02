package io.nagode.domain;
import java.util.UUID;
public final class Models { private Models() {} public enum Direction { DEBIT, CREDIT } public enum LedgerType { PAYMENT, REFUND, REVERSAL, FEE } public record Posting(UUID accountId, Direction direction, long amount) {} }
