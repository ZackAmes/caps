import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	// Expose non-VITE-prefixed env vars we rely on to the client bundle.
	// RPC_KEY is set in Vercel project env; locally use a .env file.
	envPrefix: ['VITE_', 'RPC_KEY'],
	server: {
		fs: {
			allow: ['..']
		}
	},
});
