const fs = require("fs");
const http = require("http");
const path = require("path");

const basePath = process.env.EFS_PATH || path.join(__dirname, "v1");
const filePath = path.join(basePath, "data.txt");

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200);
    res.end("SEHAT");
    return;
  }
  try {
    const content = fs.readFileSync(filePath, "utf8");
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(`APPS VERSION 2. READ FROM EFS:\n${content}`);
  } catch (err) {
    res.writeHead(500);
    res.end(`ERROR: ${err.message}`);
  }
});

server.listen(3000, () => {
  console.log("INI APPS VERSION 2");
  console.log("Server running on port 3000");
  console.log("Reading file from", filePath);
});
