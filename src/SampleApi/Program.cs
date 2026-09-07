var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHealthChecks();

var app = builder.Build();

// Native publishing path: Gateway API forwards /sample-api without rewriting it.
app.UsePathBase("/sample-api");

app.MapGet("/", () => Results.Ok(new
{
    service = "sample-api",
    status = "ok",
    version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "local",
    message = Environment.GetEnvironmentVariable("APP_MESSAGE") ?? "hello"
}));

app.MapGet("/api/hello", () => Results.Ok(new
{
    message = Environment.GetEnvironmentVariable("APP_MESSAGE") ??
              "Hello from Jenkins + BuildKit + OCIR + Argo CD"
}));

app.MapHealthChecks("/healthz");

app.Run();

public partial class Program { }
