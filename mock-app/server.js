const express = require("express");
const app = express();

// Configuration from environment variables
const PORT = process.env.PORT || 8080;
const RELEASE_ID = process.env.RELEASE_ID || "unknown";
const APP_POOL = process.env.APP_POOL || "unknown";

// State management for chaos testing
let chaosMode = null;
let chaosStartTime = null;

// Middleware for JSON parsing
app.use(express.json());

// Health check endpoint
app.get("/healthz", (req, res) => {
  if (chaosMode === "error") {
    return res.status(500).json({
      status: "unhealthy",
      chaos: true,
      mode: chaosMode,
    });
  }

  if (chaosMode === "timeout") {
    // Don't respond - let it timeout
    return;
  }

  res.json({
    status: "healthy",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Version endpoint - main application endpoint
app.get("/version", (req, res) => {
  // Apply chaos if active
  if (chaosMode === "error") {
    res.set("X-App-Pool", APP_POOL);
    res.set("X-Release-Id", RELEASE_ID);
    return res.status(500).json({
      error: "Chaos mode active",
      mode: chaosMode,
      startTime: chaosStartTime,
    });
  }

  if (chaosMode === "timeout") {
    // Don't respond - let it timeout
    return;
  }

  // Normal response with required headers
  res.set("X-App-Pool", APP_POOL);
  res.set("X-Release-Id", RELEASE_ID);

  res.json({
    version: "1.0.0",
    pool: APP_POOL,
    releaseId: RELEASE_ID,
    timestamp: new Date().toISOString(),
    hostname: require("os").hostname(),
    uptime: process.uptime(),
  });
});

// Chaos engineering endpoints
app.post("/chaos/start", (req, res) => {
  const mode = req.query.mode || "error";

  if (!["error", "timeout"].includes(mode)) {
    return res.status(400).json({
      error: 'Invalid chaos mode. Use "error" or "timeout"',
    });
  }

  chaosMode = mode;
  chaosStartTime = new Date().toISOString();

  console.log(`Chaos mode started: ${mode} at ${chaosStartTime}`);

  res.json({
    message: `Chaos mode "${mode}" started`,
    startTime: chaosStartTime,
    pool: APP_POOL,
  });
});

app.post("/chaos/stop", (req, res) => {
  const previousMode = chaosMode;
  chaosMode = null;
  chaosStartTime = null;

  console.log(`Chaos mode stopped (was: ${previousMode})`);

  res.json({
    message: "Chaos mode stopped",
    previousMode: previousMode,
    stoppedAt: new Date().toISOString(),
    pool: APP_POOL,
  });
});

// Chaos status endpoint
app.get("/chaos/status", (req, res) => {
  res.json({
    active: chaosMode !== null,
    mode: chaosMode,
    startTime: chaosStartTime,
    pool: APP_POOL,
  });
});

// Root endpoint
app.get("/", (req, res) => {
  res.json({
    message: "Mock Blue/Green Application",
    pool: APP_POOL,
    releaseId: RELEASE_ID,
    endpoints: {
      version: "/version",
      health: "/healthz",
      chaos: {
        start: "POST /chaos/start?mode=error|timeout",
        stop: "POST /chaos/stop",
        status: "GET /chaos/status",
      },
    },
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error("Error:", err);
  res.status(500).json({
    error: "Internal server error",
    pool: APP_POOL,
  });
});

// Start server
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Mock app started on port ${PORT}`);
  console.log(`Pool: ${APP_POOL}`);
  console.log(`Release ID: ${RELEASE_ID}`);
  console.log(`Started at: ${new Date().toISOString()}`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("Received SIGTERM, shutting down gracefully");
  process.exit(0);
});

process.on("SIGINT", () => {
  console.log("Received SIGINT, shutting down gracefully");
  process.exit(0);
});
