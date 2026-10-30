import { NextRequest,NextResponse } from 'next/server';
import { generateText } from 'ai';
import { createGoogle } from '@ai-sdk/google';
import { z } from 'zod';
import { authenticated } from '@/lib/server-auth';
import { allowedModels,defaultModel,encryptCredential,providerConfiguration } from '@/lib/provider';
export const runtime='nodejs';export const maxDuration=30;
export async function GET(request:NextRequest){try{const {db}=await authenticated(request);const config=await providerConfiguration(db);return NextResponse.json({connected:Boolean(config),model:config?.model||defaultModel});}catch{return NextResponse.json({connected:false},{status:401});}}
export async function POST(request:NextRequest){
 try{
  const {db}=await authenticated(request);const {data:profile,error}=await db.rpc('ensure_profile');if(error||profile.role!=='manager')return NextResponse.json({error:'A manager must connect the workspace AI.'},{status:403});
  const raw=await request.text();if(raw.length>2000)return NextResponse.json({error:'Request too large'},{status:413});
  const body=z.object({apiKey:z.string().trim().min(20).max(250),model:z.enum(['gemini-3.5-flash-lite','gemini-3.8-flash']).default(defaultModel as 'gemini-3.5-flash-lite'),confirmFreeTier:z.literal(true)}).parse(JSON.parse(raw));
  if(!allowedModels.includes(body.model))throw new Error('Unsupported model');
  const context=await db.rpc('workspace_context');if(!context.data?.cloud_ai_allowed)throw new Error('Enable company AI permission first');
  const model=createGoogle({apiKey:body.apiKey})(body.model);
  const result=await generateText({model,prompt:'Reply with the single word CONNECTED.',maxOutputTokens:64,maxRetries:0,abortSignal:AbortSignal.timeout(12000)});
  if(!result.text.toUpperCase().includes('CONNECTED'))throw new Error('Model connection test did not complete.');
  const saved=await db.rpc('save_provider_configuration',{p_secret:process.env.REVIEW_SERVER_SECRET,p_configuration:{encrypted_key:encryptCredential(body.apiKey),model:body.model,connected_at:new Date().toISOString()}});
  if(saved.error)throw new Error('Could not securely save the connection.');
  return NextResponse.json({connected:true,model:body.model});
 }catch{return NextResponse.json({error:'Could not connect. Verify manager two-factor authentication and company cloud-AI permission, then check your key, model and quota. No key was saved if the test failed.'},{status:400});}
}
export async function DELETE(request:NextRequest){try{const {db}=await authenticated(request);const r=await db.rpc('save_provider_configuration',{p_secret:process.env.REVIEW_SERVER_SECRET,p_configuration:null});if(r.error)return NextResponse.json({error:'Only a manager can disconnect the provider.'},{status:403});return NextResponse.json({connected:false});}catch{return NextResponse.json({error:'Sign in first'},{status:401});}}
