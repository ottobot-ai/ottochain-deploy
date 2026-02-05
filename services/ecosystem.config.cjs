module.exports = {
  apps: [
    {
      name: "monitor",
      script: "packages/monitor/dist/index.js",
      cwd: "/opt/ottochain-services",
      env: {
        // Only primary nodes accessible through firewall
        GL0_URLS: "http://5.78.90.207:9000",
        ML0_URLS: "http://5.78.90.207:9200",
        CL1_URLS: "http://5.78.90.207:9300",
        DL1_URLS: "http://5.78.90.207:9400",
        BRIDGE_URL: "http://localhost:3030",
        INDEXER_URL: "http://localhost:3031",
        GATEWAY_URL: "http://localhost:4000",
        POLL_INTERVAL_MS: "10000",
        MONITOR_PORT: "3032",
        MONITOR_AUTH: "false",
        TELEGRAM_BOT_TOKEN: "8387278288:AAEK0iOOkf28EyGY11wjfCR4PWdAsCUABmk",
        TELEGRAM_CHAT_ID: "7910600397",
      },
    },
    {
      name: "bridge",
      script: "packages/bridge/dist/index.js",
      cwd: "/opt/ottochain-services",
    },
    {
      name: "indexer",
      script: "packages/indexer/dist/index.js", 
      cwd: "/opt/ottochain-services",
    },
    {
      name: "gateway",
      script: "packages/gateway/dist/index.js",
      cwd: "/opt/ottochain-services",
    },
    {
      name: "traffic-gen",
      script: "packages/traffic-generator/dist/index.js",
      cwd: "/opt/ottochain-services",
    },
  ],
};
