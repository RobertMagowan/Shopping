FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8080
ENV ASPNETCORE_HTTP_PORTS=8080
ENV ASPNETCORE_FORWARDEDHEADERS_ENABLED=true

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["src/Shopping.Contracts/Shopping.Contracts.csproj", "src/Shopping.Contracts/"]
COPY ["src/Shopping.Web/Shopping.Web.csproj", "src/Shopping.Web/"]
RUN dotnet restore "src/Shopping.Web/Shopping.Web.csproj"
COPY src/ src/
RUN dotnet publish "src/Shopping.Web/Shopping.Web.csproj" \
    --configuration "$BUILD_CONFIGURATION" \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false
RUN test -f /app/publish/wwwroot/_framework/blazor.web.js

FROM runtime AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
ENTRYPOINT ["dotnet", "Shopping.Web.dll"]
