{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:

buildNpmPackage rec {
  pname = "opencode-cursor";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "stablekernel";
    repo = "opencode-cursor";
    rev = "577371b641d76e4a7c1dc7c9672c785f6cb58bdd";
    hash = "sha256-nOZ+E21Ew3/4K+VdvaWWP+d8a2HcywsyG1n6UZSauUM=";
  };

  npmDepsHash = "sha256-o8eJE7RVlNgma2G/udnRSkeY9FjIispSeTfVg/oBQ28=";
  npmBuildScript = "build";
  doCheck = true;

  postPatch = ''
    substituteInPlace src/sidecar/agent-host.mjs \
      --replace-fail \
        'sdkPromise ??= import(process.env.OPENCODE_CURSOR_SDK_PATH || "@cursor/sdk");' \
        'sdkPromise ??= import(process.env.OPENCODE_CURSOR_SDK_PATH || "@cursor/sdk").then((sdk) => { if (process.env.OPENCODE_CURSOR_SIDECAR_HTTP1 === "1") sdk.Cursor.configure({ local: { useHttp1ForAgent: true } }); return sdk; });'

    substituteInPlace src/model-discovery.ts \
      --replace-fail \
        $'  /** Bypass the on-disk cache and force a live `Cursor.models.list()`. */\n  forceRefresh?: boolean;' \
        $'  /** Bypass the on-disk cache and force a live `Cursor.models.list()`. */\n  forceRefresh?: boolean;\n  /** Allow CURSOR_API_KEY fallback when no explicit key is provided. */\n  useEnvApiKey?: boolean;' \
      --replace-fail \
        '  const apiKey = resolveCursorApiKey(options.apiKey);' \
        '  const apiKey = options.useEnvApiKey === false ? options.apiKey?.trim() || undefined : resolveCursorApiKey(options.apiKey);'

    substituteInPlace src/plugin/index.ts \
      --replace-fail \
        $'\t\tconfig: async (config) => {\n\t\t\tconst { models } = await discoverModels({});' \
        $'\t\tconfig: async (config) => {\n\t\t\tconst { models } = await discoverModels({ useEnvApiKey: false });'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/opencode-cursor"
    cp -r dist node_modules package.json "$out/lib/opencode-cursor/"
    runHook postInstall
  '';

  meta = {
    description = "Native Cursor provider for OpenCode";
    homepage = "https://github.com/stablekernel/opencode-cursor";
    license = lib.licenses.mit;
  };
}
