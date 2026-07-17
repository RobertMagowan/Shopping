FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENV ASPNETCORE_FORWARDEDHEADERS_ENABLED=true

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/Shopping.Api/Shopping.Api.csproj", "src/Shopping.Api/"]
COPY ["src/Shopping.Application/Shopping.Application.csproj", "src/Shopping.Application/"]
COPY ["src/Shopping.Contracts/Shopping.Contracts.csproj", "src/Shopping.Contracts/"]
COPY ["src/Shopping.Domain/Shopping.Domain.csproj", "src/Shopping.Domain/"]
COPY ["src/Shopping.Infrastructure/Shopping.Infrastructure.csproj", "src/Shopping.Infrastructure/"]
RUN dotnet restore "src/Shopping.Api/Shopping.Api.csproj"
COPY src/ src/
RUN dotnet publish "src/Shopping.Api/Shopping.Api.csproj" \
    --configuration "$BUILD_CONFIGURATION" \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "Shopping.Api.dll"]
