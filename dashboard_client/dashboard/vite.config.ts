import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Standalone deploy: relative base zodat de build vanaf elke map/server werkt.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    outDir: 'dist',
    chunkSizeWarningLimit: 1500,
  },
})
