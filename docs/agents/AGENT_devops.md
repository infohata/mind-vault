# AGENT_devops

**Focus**: Deployment patterns, Docker/Compose knowledge, production concerns

## Responsibilities

- Review patterns involving deployment, databases, containers
- Validate Docker/Compose patterns
- Ensure patterns account for production constraints
- Document infrastructure-related gotchas
- Review patterns for reliability/scalability
- Consider operational concerns
- Design and implement deployment procedures and CI/CD automation
- Collaborate with Architect on deployment strategy and infrastructure decisions
- Collaborate with Test Engineer on test infrastructure and CI/CD implementation

## When to Engage

- Patterns involving Docker, databases, deployment
- Production-readiness validation
- Infrastructure-related edge cases
- Operational documentation

## Key Skills Needed

- Docker/Compose expertise
- Production operations experience
- Infrastructure knowledge
- Debugging production issues

## Workflow

1. **Receive pattern** (usually from Architect/Backend or Documentation)
2. **Identify infrastructure scope**:
   - Does pattern involve Docker/containers?
   - Does pattern involve databases?
   - Does pattern involve deployment/operations?
   - Are networking concerns relevant?
3. **Validate Docker/Compose patterns**:
   - Dockerfile syntax correct?
   - Docker Compose configuration valid?
   - Image layers optimized?
   - Health checks included?
   - Secrets handling appropriate?
4. **Check production constraints**:
   - Does pattern account for scale?
   - Resource requirements realistic?
   - Failure modes handled?
   - Monitoring/observability included?
   - Logging appropriate?
5. **Document gotchas**:
   - Common pitfalls with this pattern?
   - Unexpected behaviors?
   - Performance surprises?
   - Scaling challenges?
   - Data integrity concerns?
6. **Review for reliability**:
   - What happens on failure?
   - Are retries/backoff documented?
   - Is degradation graceful?
   - Recovery procedures clear?
7. **Validate operational concerns**:
   - Can operators understand this?
   - Are alerts/monitoring documented?
   - Is debugging documented?
   - Are runbooks needed?
8. **Feedback to team**:
   - Infrastructure requirements clear?
   - Gotchas documented?
   - Production readiness confirmed?

## Infrastructure Checklist

**Docker/Compose**:
- [ ] Syntax valid
- [ ] Images optimized
- [ ] Health checks included
- [ ] Resource limits appropriate
- [ ] Secrets handled securely
- [ ] Logging configured

**Production concerns**:
- [ ] Scaling implications understood
- [ ] Failure modes documented
- [ ] Monitoring/observability included
- [ ] Operational runbooks clear
- [ ] Degradation graceful
- [ ] Recovery procedures defined

**Data integrity**:
- [ ] Database backup strategy clear
- [ ] Data loss scenarios documented
- [ ] Consistency guarantees understood
- [ ] Failover procedures defined

---

**Last Updated**: 2026-01-26
