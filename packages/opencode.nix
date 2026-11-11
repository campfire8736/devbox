{ lib, stdenv, fetchurl }:
# Pinned upstream release rather than nixpkgs: nixos-26.05 still ships 1.x,
# and this keeps the CLI version independent of the channel.
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "2.2.7";

  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-linux-x64.tar.gz";
    hash = "sha256-iabO4ie1S8ARF5xSil5jF2AyRisaXiFyO2FoAc3cLKc=";
  };

  sourceRoot = ".";

  unpackPhase = ''
    runHook preUnpack
    tar xzf $src
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode $out/bin/opencode
    runHook postInstall
  '';

  meta = {
    description = "OpenCode AI coding agent (CLI, API and web server)";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
