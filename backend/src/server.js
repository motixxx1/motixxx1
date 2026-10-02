import { createServer } from 'node:http';
import { createApp } from './app.js';
import { Marketplace } from './marketplace.js';

const market = new Marketplace({ notify: (proId, msg) => console.log('[push]', proId, msg) });
const port = process.env.PORT || 3000;
createServer(createApp(market)).listen(port, () => console.log(`API on http://localhost:${port}`));
