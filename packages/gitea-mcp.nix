{ lib, stdenv, fetchurl }:
stdenv.mkDerivation (finalAttrs: {
  pname = "gitea-mcp";
  version = "1.13.0";

  src = fetchurl {
    url = "https://gitea.com/gitea/gitea-mcp/releases/download/v${finalAttrs.version}/gitea-mcp_Linux_x86_64.tar.gz";
    hash = "sha256-Izg61q27eopqhIrHNsB94ZQX0mMRw1gRYLNW2wGzNm0=";
  };

  sourceRoot = ".";

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 gitea-mcp $out/bin/gitea-mcp
    runHook postInstall
  '';

  meta = {
    description = "Gitea's official MCP server";
    homepage = "https://gitea.com/gitea/gitea-mcp";
    license = lib.licenses.mit;
    mainProgram = "gitea-mcp";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
