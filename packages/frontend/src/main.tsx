/// <reference types="vite/client" />
import React from 'react';
import ReactDOM from 'react-dom/client';
import * as Sentry from '@sentry/react';
import App from './App';
import './index.css';

// ============================================================================
// ErrorBoundary — Manejo de errores de React (Factor VI - Robustez)
// ============================================================================

interface Props {
  children: React.ReactNode;
}

interface State {
  hasError: boolean;
  error?: Error;
}

class ErrorBoundary extends React.Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false };
  }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    if (import.meta.env.VITE_SENTRY_DSN) {
      Sentry.captureException(error, { 
        contexts: { 
          react: { componentStack: errorInfo.componentStack } 
        } 
      });
    }
    console.error('ErrorBoundary capturó error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen bg-gradient-to-b from-red-50 to-red-100 flex items-center justify-center px-4">
          <div role="alert" aria-live="assertive" className="bg-white rounded-lg shadow-lg p-8 max-w-md">
            <h1 className="text-2xl font-bold text-gray-900 text-center mb-2">
              Error inesperado
            </h1>
            <p className="text-gray-600 text-center mb-4">
              La aplicación encontró un problema. Por favor, intenta recargar la página.
            </p>
            {this.state.error && (
              <pre className="text-xs text-red-600 bg-gray-50 p-3 rounded mt-2 overflow-auto max-h-32 font-mono">
                {this.state.error.message}
              </pre>
            )}
            <button
              onClick={() => {
                this.setState({ hasError: false, error: undefined });
                window.location.reload();
              }}
              className="mt-4 w-full bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-2"
            >
              Recargar página
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

// ============================================================================
// Inicializar Sentry
// ============================================================================

if (import.meta.env.VITE_SENTRY_DSN) {
  Sentry.init({
    dsn: import.meta.env.VITE_SENTRY_DSN,
    environment: import.meta.env.MODE || 'development',
    tracesSampleRate: import.meta.env.MODE === 'production' ? 0.1 : 1.0,
  });
}

// ============================================================================
// Renderizar con ErrorBoundary
// ============================================================================

const rootElement = document.getElementById('root');
if (!rootElement) throw new Error('Failed to find the root element');

const root = ReactDOM.createRoot(rootElement);
root.render(
  <React.StrictMode>
    <ErrorBoundary>
      <App />
    </ErrorBoundary>
  </React.StrictMode>
);