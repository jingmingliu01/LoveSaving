package com.lovesaving.aiinsights.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class FirestoreInsightStorageTest {

    @Test
    void memoryDocumentIdIsScopedByOwnerAndGroup() {
        assertThat(FirestoreInsightStorage.memoryDocumentId("user-123", "group-456"))
            .isEqualTo("user-123__group-456");
    }

    @Test
    void formatEventPayloadMatchesExistingEventShape() {
        assertThat(
            FirestoreInsightStorage.formatEventPayload(
                "deposit",
                3,
                2,
                "Brought coffee after a stressful day",
                "2026-03-31T13:45:00Z",
                "Boston Common"
            )
        ).isEqualTo(
            "type=deposit | delta=3 | tapCount=2 | occurredAt=2026-03-31T13:45:00Z | location=Boston Common | note=Brought coffee after a stressful day"
        );
    }
}
