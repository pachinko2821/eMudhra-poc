const dns = require("dns").promises;
const axios = require("axios");

const urls = [
  "https://dv-g3b-emudhra.we-have-a-problem.com/",
  "https://dv-g3b-aaa-emudhra.we-have-a-problem.com/",
];

async function fetchUrl(url) {
  console.log(`[Node.js ${process.version}] Requesting: ${url}`);
  try {
    const res = await axios.get(url, { timeout: 10000 });
    console.log(
      `[Node.js ${process.version}] -> Status: ${res.status} (${url})`,
    );
  } catch (err) {
    const msg = err.response
      ? `Status ${err.response.status}`
      : `${err.code || err.name}: ${err.message}`;
    console.log(`[Node.js ${process.version}] -> FAILED: ${msg} for ${url}`);
  }
}

async function testLocalNginx() {
  const domain = process.env.DOMAIN || "google.com";
  console.log(
    `\n[Node.js ${process.version}] Testing local Nginx connection to https://${domain}/ (resolved via /etc/hosts)...`,
  );

  try {
    const lookup = await dns.lookup(domain);
    console.log(
      `[Node.js ${process.version}] /etc/hosts resolved ${domain} -> ${lookup.address}`,
    );
  } catch (err) {
    console.log(
      `[Node.js ${process.version}] DNS lookup failed for ${domain}: ${err.message}`,
    );
  }

  try {
    const res = await axios.get(`https://${domain}/`, { timeout: 10000 });
    console.log(
      `[Node.js ${process.version}] SUCCESS! Node.js axios verified certificate for https://${domain}/. Status: ${res.status}. Text: ${res.data}`,
    );
  } catch (err) {
    const msg = err.response
      ? `Status ${err.response.status}`
      : `${err.code || err.name} - ${err.message}`;
    console.log(
      `[Node.js ${process.version}] FAILED! Node.js axios Error: ${msg}`,
    );
  }
}

async function run() {
  console.log(
    `--- [Node.js ${process.version}] Starting External Domain Checks (using axios) ---`,
  );
  for (const url of urls) {
    await fetchUrl(url);
  }
  console.log(`--- [Node.js ${process.version}] External Checks Done ---`);
  await testLocalNginx();
}

run();
