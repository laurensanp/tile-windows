# Builds a minimal unsigned shortcut that shows "Hello from GitHub".
import plistlib, sys
wf = {
    "WFWorkflowActions": [{
        "WFWorkflowActionIdentifier": "is.workflow.actions.showresult",
        "WFWorkflowActionParameters": {"Text": "Hello from GitHub – signing works!"},
    }],
    "WFWorkflowClientVersion": "2302.0.4",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFQuickActionSurfaces": [],
    "WFWorkflowHasShortcutInputVariables": False,
}
with open(sys.argv[1], "wb") as f:
    plistlib.dump(wf, f, fmt=plistlib.FMT_BINARY)
