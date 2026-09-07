var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();

var app = builder.Build();

app.MapGet("/", () => Results.Ok(new
{
    service = "sample-api",
    status = "ok",
    version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "local"
}));

app.MapGet("/api/hello", () => Results.Ok(new
{
    message = "Hello from Jenkins + OCIR + Argo CD"
}));

app.MapHealthChecks("/healthz");
app.Run();

public partial class Program { }
