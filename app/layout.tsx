import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'InvoiceFlow — A clearer path to approval', description: 'Review invoices, verify every detail, and keep people in control. A traceable invoice approval workspace.' };
export default function RootLayout({ children }: { children: React.ReactNode }) { return <html lang="en"><body>{children}</body></html>; }
