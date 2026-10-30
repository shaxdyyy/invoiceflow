import { NextRequest,NextResponse } from 'next/server';
import { z } from 'zod';
import { authenticated } from '@/lib/server-auth';
export async function GET(req:NextRequest){try{const {db}=await authenticated(req);const id=z.uuid().parse(req.nextUrl.searchParams.get('id'));const {data,error}=await db.rpc('assess_invoice',{p_id:id});if(error)throw error;const c=await db.from('exception_cases').select('*').eq('invoice_id',id).maybeSingle();return NextResponse.json({assessment:data,exception:c.data});}catch{return NextResponse.json({error:'Could not load invoice controls. Check access and database setup.'},{status:400});}}
