import {apiHeaders} from './api-client';
export async function privateDocumentFile(id:string){const r=await fetch(`/api/document-file?id=${encodeURIComponent(id)}`,{headers:await apiHeaders(),cache:'no-store'});if(!r.ok)throw new Error('Document not accessible. Sign in again or verify your company and two-factor authentication.');return r.blob();}
