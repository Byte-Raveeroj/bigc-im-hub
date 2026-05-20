module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { entries, exportedAt, project } = req.body;
  if (!Array.isArray(entries) || entries.length === 0)
    return res.status(400).json({ error: 'No entries' });

  const token = process.env.GITHUB_TOKEN;
  if (!token) return res.status(500).json({ error: 'GITHUB_TOKEN not configured' });

  const filename = `updates/${Date.now()}.json`;
  const content = Buffer.from(
    JSON.stringify({ exportedAt, project, entries }, null, 2)
  ).toString('base64');

  const response = await fetch(
    `https://api.github.com/repos/Byte-Raveeroj/bigc-im-hub/contents/${filename}`,
    {
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'bigc-im-hub-sync'
      },
      body: JSON.stringify({
        message: `update: ${entries.length} entries from Hub`,
        content
      })
    }
  );

  if (!response.ok) {
    const err = await response.json();
    return res.status(500).json({ error: err.message });
  }

  return res.status(200).json({ success: true, filename, count: entries.length });
};
