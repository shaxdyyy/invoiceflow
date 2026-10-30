import { NextRequest, NextResponse } from 'next/server';
import { requestDatabase } from '@/lib/supabase';
import { reviewInvoice } from '@/lib/agent';
import { z } from 'zod';
export const runtime = 'nodejs';
export const maxDuration = 60;
export async function POST(request: NextRequest) {
  if (Number(request.headers.get('content-length') || 0) > 2000) return NextResponse.json({ error: 'Request too large' }, { status: 413 });
  const origin = request.headers.get('origin');
  if (origin && origin !== request.nextUrl.origin) return NextResponse.json({ error: 'Invalid request origin' }, { status: 403 });
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return NextResponse.json({ error: 'Sign in to review an invoice' }, { status: 401 });
  if (!process.env.REVIEW_SERVER_SECRET) return NextResponse.json({ error: 'Review server needs configuration. See Setup in the guide.' }, { status: 503 });
  try {
    const raw = await request.text();
    if (raw.length > 2000) return NextResponse.json({ error: 'Request too large' }, { status: 413 });
    const body = z.object({ invoiceId: z.uuid() }).parse(JSON.parse(raw));
    const db = requestDatabase(token);
    const { data: identity, error: authError } = await db.auth.getUser(token);
    if (authError || !identity.user) return NextResponse.json({ error: 'Session expired. Sign in again.' }, { status: 401 });
    const { data, error } = await db.rpc('start_review', { p_id: body.invoiceId });
    if (error) return NextResponse.json({ error: error.message }, { status: 409 });
    if (data.status !== 'processing') return NextResponse.json({ invoice: data, noop: true });
    const result = await reviewInvoice(data);
    const finished = await db.rpc('finish_review', { p_id: data.id, p_run_id: data.run_id, p_secret: process.env.REVIEW_SERVER_SECRET, p_result: result });
    if (finished.error) return NextResponse.json({ error: finished.error.message }, { status: 409 });
    return NextResponse.json({ invoice: finished.data });
  } catch (error) {
    return NextResponse.json({ error: error instanceof z.ZodError || error instanceof SyntaxError ? 'Invalid invoice identifier' : 'Review could not complete. Retry after two minutes if it remains in progress.' }, { status: 400 });
  }
}
