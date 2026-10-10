/**
 * TicoTax Frontend — Componente App
 * Épica TICOTAX-100 | Sprint 1 (Semanas 1-2) | Historia TICOTAX-102
 * 
 * Stub para TICOTAX-203 (Maqueta Frontend).
 * Factor XI (Logs): el frontend no genera logs; Sentry captura errores.
 */

export default function App() {
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <main className="text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          TicoTax
        </h1>
        <p className="text-gray-600 text-lg mb-8">
          Gestor de Facturas Electrónicas para Costa Rica
        </p>
        <div className="space-y-4">
          <p className="text-sm text-gray-600">
            Ambiente: <code className="bg-gray-200 px-2 py-1 rounded">{import.meta.env.MODE}</code>
          </p>
          <p className="text-sm text-gray-600">
            API: <code className="bg-gray-200 px-2 py-1 rounded">{import.meta.env.VITE_API_BASE_URL}</code>
          </p>
        </div>
        {/* text-gray-400 sobre bg-gray-50 no cumple el contraste 4.5:1 de WCAG 2.1 AA */}
        <p className="text-xs text-gray-500 mt-8">
          En desarrollo — {new Date().toISOString()}
        </p>
      </main>
    </div>
  );
}