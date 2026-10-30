import { writeFileSync } from 'node:fs';
import { runScenarios } from '../lib/scenarios';
const results=runScenarios();
const text=`# Automated scenario report\n\nGenerated: ${new Date().toISOString()}\n\nThese are executable checker and policy scenarios, not a claim that a live model was tested. Database permission and transaction tests are recorded separately.\n\n| Scenario | Expected | Result |\n|---|---|---|\n`+results.map(r=>`| ${r.name} | ${r.expected} | ${r.passed?'PASS':'FAIL'} |`).join('\n')+'\n';
writeFileSync('docs/TEST_REPORT.md',text); console.log(`${results.filter(r=>r.passed).length}/${results.length} scenarios passed`);
if(results.some(r=>!r.passed))process.exitCode=1;
