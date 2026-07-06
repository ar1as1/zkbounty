module.exports = {
  content: [
    "./index.html",
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  safelist: [
    'bg-green-900', 'bg-yellow-900', 'bg-blue-900', 
    'bg-gray-700', 'bg-orange-900', 'bg-red-900',
    'text-green-300', 'text-yellow-300', 'text-blue-300',
    'text-gray-300', 'text-green-400', 'text-yellow-400',
    'text-orange-400', 'text-red-500', 'text-white',
    'border-green-700', 'border-yellow-700', 'border-red-800',
  ],
  theme: { extend: {} },
  plugins: [],
}
