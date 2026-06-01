# Known Issues

This file tracks deliberately-deferred bugs and tech debt that have been acknowledged, assigned a severity, and scheduled for a future fix phase. An issue appearing here is not ignored — it is owned. Issues are closed when the fix is merged and verified; they are never silently dropped.

---

| ID | Severity | Component | Description | Found | Target Fix | Status |
|----|----------|-----------|-------------|-------|------------|--------|
| KI-001 | **High** | `AK.Discount.Grpc` | `AuthInterceptor` reads `realm_access.roles` (Keycloak JWT structure) instead of the Entra flat `roles` claim. Admin write RPCs — `CreateDiscount`, `UpdateDiscount`, `DeleteDiscount` — return `PermissionDenied` for all Entra tokens. Read RPCs (`GetDiscount`, `GetAllDiscounts`, `GetDiscountByProductId`) are unguarded and unaffected. | Week 6 pre-flight testing | Integration-testing phase (Weeks 7–9) | Open |
| KI-002 | **Low** | `AK.Order` / `AK.Payments` | `Microsoft.EntityFrameworkCore.Relational` resolved to mixed 9.0.1 / 9.0.4 due to `MassTransit.EntityFrameworkCore 8.3.6` pinning 9.0.1 as a direct dependency. MSB3277 warning was silenced by adding explicit 9.0.4 pins to `Order.Infrastructure`, `Payments.Infrastructure`, `Notification.Infrastructure`, and `Notification.Functions` `.csproj` files. Verify the warning is fully gone with a clean `dotnet build` before closing. | Week 4 build | Before Week 6 end-to-end / housekeeping | Open — verify after warning cleanup |
