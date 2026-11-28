# macOS native Quit diagnostic follow-up

Prepared 2026-11-18 after P05.81 product4c6f6de platform44233632031 nativeQuit failure. This is a separate validation slice to register after feat-133 evidence closeout, not a product shutdown fix or completed acceptance.

Evidence: macOS job134564401396 found PID31313 at the expected Release bundle, active=true, then reported AX selected `flutterMenuItemSelected: > flutterMenuItemSelected:` and wrapper still alive after20seconds. Prior e865b11 instead fell back to postedCommand-Q. Neither proves precise menu match or actual appPID state at timeout. Preserve both failures.

Minimal helper/workflow diagnostics:

1. Snapshot matching bundle-ID/canonical-path instances before `open -n -W`. Bind exactlyone new instance, including PID, launchdate and canonical bundle/executable path; zero/multiple/unknown is a bindingfailure. Never select the lastmatchinginstance. Require theQuit helper tovalidateanduse this boundidentity.
2. Observe actualapplication and open-Wwrapper independently within the existing20secondbudget. Appalive alwaysfails; appgone/wrapperalive remainsunresolvedfailure; appgone/wrappernonzero fails; onlybothgoneandwrapperzero meets existing exit-observationcriterion. Unknownidentity fails. Callwrapperstatus open_status, notapp_status.
3. Preservecurrentmenuselectionbehavior but logAX attributes separately (identifier/title/description/label/value/role/subrole/enabled), commandcharacter/modifiers, parent/entryindices and exactmatchreason beforeAXPress; logpressresult. Genericdisplaylabelalone doesnotprovewrongselection.
4. Timestamp/flushbinding, eachselection/fallbackstage andfinalstate. Beforecleanup capturepsforbothPIDs andboundedwindowsummary; sampleonlyvalidatedliveapplication. Cleanupboundapplicationandwrapper independently, preservefailurestatus, donotpkillallalula_appbyname.

Acceptance: helper argument/identity parsing and lifecycle classifications tested whereplatformallows; workflowYAML/shellsyntax validated; exactmacOShostedrun saves targetidentity/state transitions andAXmatch evidence. Do notextendtimeouts, waivefailures, tightenmatcher orchangeFlutter/AppKitclosebehavior inthisdiagnostic slice. A later productfix mustfollow actualevidence.

Graph: helperimpactCRITICAL withrundirectcaller; privateDartclosehelpersUNKNOWN andsource-reviewed. Re-runcurrentimpactbeforeediting. ParentP05/nativenativeQuit acceptance staysopenuntilreal evidence resolves it.
