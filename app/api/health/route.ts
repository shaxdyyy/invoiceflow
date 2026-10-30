import { NextResponse } from 'next/server';
export const dynamic = 'force-dynamic';
export function GET() { return NextResponse.json({ application: 'InvoiceFlow', databaseConfigured: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY), reviewConfigured: Boolean(process.env.REVIEW_SERVER_SECRET), aiConfigured: Boolean(process.env.GOOGLE_GENERATIVE_AI_API_KEY), aiMode: process.env.GOOGLE_GENERATIVE_AI_API_KEY ? 'ai' : 'rules', paidFallback: false }); }
