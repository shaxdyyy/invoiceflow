# InvoiceFlow

InvoiceFlow is a web application for organizing invoice submissions and review. It combines document upload, structured invoice details, arithmetic checks, and a manager review workflow.

## Features

- Upload and review invoice documents.
- Check line items, taxes, and totals with deterministic calculations.
- Use configured AI providers for document reading and the invoice assistant.
- Keep a clear review step for uncertain extracted information.
- Try two fictional practice invoices to see the upload and review flow.

## Practice invoices

The two sample PDFs are in [`public/samples`](public/samples). They contain fictional data and are clearly marked as practice documents. In the application, those exact samples use a five-second demonstration flow and display prepared extraction results; they do not call an AI provider.

## Important

InvoiceFlow is a prototype. Review extracted values against the source document before making business decisions. The practice invoices are not real bills and must not be paid.
