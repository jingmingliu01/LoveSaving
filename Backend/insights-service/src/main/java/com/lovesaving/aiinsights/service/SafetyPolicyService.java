package com.lovesaving.aiinsights.service;

import java.util.Locale;
import org.springframework.stereotype.Service;

@Service
public class SafetyPolicyService {

    private final ModerationGateway moderationGateway;
    private final SafetyResponseFactory responseFactory;

    public SafetyPolicyService(
        ModerationGateway moderationGateway,
        SafetyResponseFactory responseFactory
    ) {
        this.moderationGateway = moderationGateway;
        this.responseFactory = responseFactory;
    }

    public SafetyDecision evaluate(String userMessage) {
        String normalized = normalize(userMessage);
        SafetyDecision localDecision = evaluateLocalRules(normalized);
        if (localDecision.isHighRisk()) {
            return localDecision;
        }

        SafetyModerationResult moderation = moderationGateway.classify(userMessage);
        SafetyDecision moderationDecision = evaluateModeration(moderation);
        if (moderationDecision.isHighRisk()) {
            return moderationDecision;
        }
        if (localDecision.level() == SafetyLevel.SUPPORT_WITH_DISCLAIMER) {
            return localDecision;
        }
        if (moderationDecision.level() == SafetyLevel.SUPPORT_WITH_DISCLAIMER) {
            return moderationDecision;
        }

        return SafetyDecision.normal();
    }

    private SafetyDecision evaluateLocalRules(String message) {
        if (containsAny(message, "how do i kill myself", "best way to kill myself", "how to kill myself", "how do i end my life")) {
            return responseFactory.refusal(SafetyCategory.SELF_HARM);
        }
        if (containsAny(message, "i am going to kill myself", "i'm going to kill myself", "i will kill myself", "i want to die now")) {
            return responseFactory.emergency(SafetyCategory.SELF_HARM);
        }
        if (containsAny(message, "i am going to hurt myself", "i'm going to hurt myself", "i will hurt myself")) {
            return responseFactory.emergency(SafetyCategory.SELF_HARM);
        }
        if (containsAny(message, "i am going to kill my partner", "i'm going to kill my partner", "i will kill my partner")) {
            return responseFactory.emergency(SafetyCategory.HARM_TO_OTHERS);
        }
        if (containsAny(message, "how do i hurt my partner", "how can i hurt my partner", "how do i scare my partner")) {
            return responseFactory.refusal(SafetyCategory.HARM_TO_OTHERS);
        }
        if (containsAny(message, "track my partner", "spy on my partner", "blackmail my partner", "control my partner", "make my partner afraid")) {
            return responseFactory.refusal(SafetyCategory.COERCIVE_CONTROL);
        }
        if (containsAny(message, "my partner is hitting me right now", "my partner is hurting me right now", "i am not safe at home right now")) {
            return responseFactory.emergency(SafetyCategory.RELATIONSHIP_ABUSE);
        }
        if (containsAny(message, "depressed", "anxious", "panic attack", "trauma", "therapist", "therapy", "emotionally abusive", "relationship abuse")) {
            return responseFactory.supportWithDisclaimer(SafetyCategory.MENTAL_HEALTH);
        }
        if (containsAny(message, "suicide", "self harm", "self-harm", "hurt myself", "want to die")) {
            return responseFactory.supportWithDisclaimer(SafetyCategory.SELF_HARM);
        }
        return SafetyDecision.normal();
    }

    private SafetyDecision evaluateModeration(SafetyModerationResult moderation) {
        if (!moderation.available() || !moderation.flagged()) {
            return SafetyDecision.normal();
        }

        if (isFlagged(moderation, "self-harm/instructions")) {
            return responseFactory.refusal(SafetyCategory.SELF_HARM);
        }
        if (isFlagged(moderation, "self-harm/intent")) {
            return responseFactory.emergency(SafetyCategory.SELF_HARM);
        }
        if (isFlagged(moderation, "violence") || isFlagged(moderation, "violence/graphic") || isFlagged(moderation, "harassment/threatening")) {
            return responseFactory.refusal(SafetyCategory.HARM_TO_OTHERS);
        }
        if (isFlagged(moderation, "self-harm")) {
            return responseFactory.supportWithDisclaimer(SafetyCategory.SELF_HARM);
        }

        return SafetyDecision.normal();
    }

    private boolean isFlagged(SafetyModerationResult moderation, String category) {
        return Boolean.TRUE.equals(moderation.categories().get(category));
    }

    private boolean containsAny(String message, String... phrases) {
        for (String phrase : phrases) {
            if (message.contains(phrase)) {
                return true;
            }
        }
        return false;
    }

    private String normalize(String value) {
        return value == null ? "" : value.toLowerCase(Locale.US);
    }
}
