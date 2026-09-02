package io.nagode.domain;

public final class Models {
  private Models() {}
  public enum Direction { DEBIT, CREDIT }
  public enum LedgerType { PAYMENT, REFUND, REVERSAL, FEE }
}
