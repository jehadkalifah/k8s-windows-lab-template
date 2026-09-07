FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/SampleApi/SampleApi.csproj src/SampleApi/
RUN dotnet restore src/SampleApi/SampleApi.csproj

COPY src/SampleApi/ src/SampleApi/
RUN dotnet publish src/SampleApi/SampleApi.csproj \
    -c Release \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION}
ENV ASPNETCORE_URLS=http://+:8080

COPY --from=build /app/publish .

EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "SampleApi.dll"]
