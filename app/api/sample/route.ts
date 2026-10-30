import { NextResponse } from 'next/server';
import { PDFDocument,StandardFonts,rgb } from 'pdf-lib';
export const runtime='nodejs';
export async function GET(){
 const pdf=await PDFDocument.create();const page=pdf.addPage([595,842]);const font=await pdf.embedFont(StandardFonts.Helvetica);const bold=await pdf.embedFont(StandardFonts.HelveticaBold);
 const write=(text:string,y:number,size=12,strong=false)=>page.drawText(text,{x:52,y,size,font:strong?bold:font,color:rgb(.12,.17,.22)});
 write('INVOICE',770,32,true);write('Fictional practice document / InvoiceFlow',742,10);
 write('Supplier: Paper & Co.',690,15,true);write('Invoice number: PRACTICE-PDF-2026-001',655);write('Invoice date: 2026-10-30',629);write('Due date: 2026-11-15',603);write('Currency: INR',577);
 page.drawLine({start:{x:52,y:551},end:{x:543,y:551},thickness:1,color:rgb(.8,.85,.9)});
 write('Description | Quantity | Unit price | Amount',520,11,true);write('A5 notebooks | 10 | 50.00 | 500.00',485);write('Desk folders | 5 | 40.00 | 200.00',454);
 page.drawLine({start:{x:52,y:427},end:{x:543,y:427},thickness:1,color:rgb(.8,.85,.9)});
 write('Tax: 0.00',392);write('Total: 700.00',350,22,true);write('This is sample data. No payment is due.',297,10);
 return new NextResponse(Buffer.from(await pdf.save()),{headers:{'Content-Type':'application/pdf','Content-Disposition':'inline; filename="invoiceflow-practice.pdf"','Cache-Control':'public, max-age=3600'}});
}
