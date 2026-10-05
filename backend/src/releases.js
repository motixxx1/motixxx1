// Files from the GitHub release (server update bundle, APKs). With GITHUB_TOKEN set they are
// fetched through the GitHub API, so the repository can stay private; without it the public
// download address is used.
export function releaseSource({ repo = 'motixxx1/motixxx1', tag = 'promarket-latest', token = '', fetchImpl = fetch, cacheMs = 5 * 60_000 } = {}) {
  let cached = null;
  const api = (path, accept = 'application/vnd.github+json') => fetchImpl(`https://api.github.com/repos/${repo}${path}`, {
    headers: { authorization: `Bearer ${token}`, accept, 'user-agent': 'Zariz-server', 'x-github-api-version': '2022-11-28' },
    redirect: 'follow',
  });
  async function assets() {
    if (cached && Date.now() - cached.at < cacheMs) return cached.list;
    const r = await api(`/releases/tags/${tag}`);
    if (!r.ok) throw new Error(`release lookup failed: HTTP ${r.status}`);
    const list = (await r.json()).assets ?? [];
    cached = { at: Date.now(), list };
    return list;
  }
  return {
    private: Boolean(token),
    // Returns a fetch Response for the named file of the release.
    async fetchAsset(name) {
      if (!token) {
        return fetchImpl(`https://github.com/${repo}/releases/download/${tag}/${name}`, { headers: { 'user-agent': 'Zariz-server' }, redirect: 'follow' });
      }
      const asset = (await assets()).find((a) => a.name === name);
      if (!asset) return new Response('not found', { status: 404 });
      return api(`/releases/assets/${asset.id}`, 'application/octet-stream');
    },
  };
}
