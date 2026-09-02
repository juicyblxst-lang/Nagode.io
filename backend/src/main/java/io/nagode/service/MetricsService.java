package io.nagode.service;
import io.micrometer.core.instrument.*;import org.springframework.stereotype.Service;
@Service public class MetricsService { public MetricsService(MeterRegistry registry){registry.gauge("nagode.ledger_imbalance",0);registry.counter("nagode.payments.created");registry.counter("nagode.webhooks.received");registry.counter("nagode.refunds.completed");} }
