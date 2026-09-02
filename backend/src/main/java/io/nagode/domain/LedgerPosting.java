package io.nagode.domain;
import java.util.UUID;
public record LedgerPosting(UUID accountId, Models.Direction direction, long amount) {}
