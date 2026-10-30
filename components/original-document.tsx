'use client';
import { useEffect,useState } from 'react';
import { ArrowUpRight,FileText,Loader2,ShieldCheck } from 'lucide-react';
import { browserDatabase } from '@/lib/supabase';
export interface DocumentRecord {id:string;owner_id:string;filename:string;mime_type:string;storage_path:string;file_size:number;invoice_id:string|null;status:string;engine:string|null;created_at:string;extraction_attempts:number;error:string|null}
export default function OriginalDocument({document,demoFile}:{document?:DocumentRecord;demoFile?:File}){
 const [url,setUrl]=useState('');const [error,setError]=useState('');const [loading,setLoading]=useState(false);
 useEffect(()=>{let current='';let active=true;if(demoFile){current=URL.createObjectURL(demoFile);setUrl(current);return()=>URL.revokeObjectURL(current);}if(document){setLoading(true);browserDatabase()!.storage.from('invoice-documents').createSignedUrl(document.storage_path,600).then(({data,error})=>{if(active){setLoading(false);if(error)setError('You cannot access this original, or the link expired. Reopen this invoice to try again.');else setUrl(data.signedUrl);}});}return()=>{active=false;};},[document?.id,demoFile]);
 const name=document?.filename||demoFile?.name;const type=document?.mime_type||demoFile?.type;
 if(!name)return null;
 return <details className="drawer-section original-document"><summary className="section-title"><h3><FileText size={16}/>Original invoice</h3><span className="tiny-tag">VIEW SOURCE ↗</span></summary><strong className="original-filename">{name}</strong>{loading&&<p className="muted"><Loader2 size={15} className="spin"/>Opening the original…</p>}{error&&<p className="form-error">{error}</p>}{url&&<>{type?.startsWith('image/')?<img src={url} alt={'Source invoice: '+name}/>:type==='application/pdf'?<iframe src={url+'#toolbar=0'} title={'Source invoice: '+name}/>:<p className="muted">A plain-text invoice is attached.</p>}<a href={url} target="_blank" rel="noreferrer" className="text-button">Open original document <ArrowUpRight size={14}/></a></>}<p className="original-access"><ShieldCheck size={13}/>{demoFile?'Demo original available until this page is refreshed.':'Private document. Access is checked before creating a temporary link.'}</p></details>;
}
