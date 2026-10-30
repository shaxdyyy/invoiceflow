import { NextRequest } from 'next/server';
import { requestDatabase } from './supabase';
export async function authenticated(request:NextRequest,options:{setup?:boolean}={}){
 const origin=request.headers.get('origin');if(origin&&origin!==request.nextUrl.origin)throw new Error('Invalid request origin');
 const token=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'');if(!token)throw new Error('Sign in to use the shared workspace.');
 const db=requestDatabase(token);const {data,error}=await db.auth.getUser(token);if(error||!data.user)throw new Error('Session expired. Sign in again.');
 if(!options.setup){const r=await db.rpc('workspace_context');if(r.error||!r.data?.workspace_id)throw new Error('Join or create a company workspace in Settings first.');if(r.data.role==='manager'&&!r.data.mfa_verified)throw new Error('Verify two-factor authentication in Settings before opening confidential company data.');}
 return {db,user:data.user};
}
