# shellcheck shell=bash
# shellcheck disable=SC2034  # sourced: these are read by make-fixture.sh and run.sh
#
# Synthetic ids, emails and names shared by tests/make-fixture.sh and
# tests/run.sh. Nothing here is real data. Ids only need to match
# [A-Za-z0-9_-]+; lengths loosely follow the shapes Drive uses (19-char 0A
# roots, 28/72-char 0B legacy ids, 33-char files and folders, 44-char docs).

# Accounts ------------------------------------------------------------------
EMAIL_A=alice@example.com   # label "example"; My Drive + Shared drives + DB
EMAIL_B=bob@gmail.com       # label "bob"; My Drive only
EMAIL_C=carol@umich.edu     # label collides with dave -> full emails
EMAIL_D=dave@umich.edu      # label collides with carol; no Chrome profile

# Numeric account ids (mount-root domain-id suffix = DriveFS/<N> dir name)
ACCT_A=1001
ACCT_B=2002
ACCT_C=3003
ACCT_D=4004

# Localized-looking top-level names are NOT hard-coded by drivethru; the
# fixture uses the English ones.
MYDRIVE="My Drive"
SHARED="Shared drives"
COMPUTERS="Other computers"

# alice@example.com -----------------------------------------------------------
A_MYDRIVE=0AAliceMyDriveRootUk9PVA
A_PROJECTS=1AliceProjectsFolderXXXXXXXXXXXX
A_PLAN=1AlicePlanDocXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_BUDGET=1AliceBudgetSheetXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_DECK=1AliceDeckSlidesXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_FORM=1AliceSurveyFormXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_SCRIPT=1AliceAutomationScriptXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_MAP=1AliceOfficeMapXXXXXXXXXXXXXXXXX
A_DRAW=1AliceWhiteboardDrawingXXXXXXXXXXXXXXXXXXXXXX
A_SITE=1AliceTeamSiteXXXXXXXXXXXXXXXXXXX
A_GDRIVE=1AliceContractDocxXXXXXXXXXXXXXXX
A_GDRIVE_KEY=0-GdriveStubKey_AbCdEfGh
A_REPORT=1AliceReportPdfXXXXXXXXXXXXXXXXXX
A_REPORTCOPY=1AliceReportCopyOwnIdXXXXXXXXXXXX   # only in the DB (inherited-id copy)
A_LEGACY=0BAliceLegacyScanPdfXXXXXXXX
A_LEGACY_KEY=0-LegacyScanKey_AbCdEfGh
A_TXT=                                           # "Draft notes.txt" has no id
A_GS=1AliceHelpersGsXXXXXXXXXXXXXXXXXXX
A_GEOJSON=1AliceRouteGeojsonXXXXXXXXXXXXXXX
A_LEGACYDIR=0BAliceLegacyArchiveFolderXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_LEGACYDIR_KEY=1-LegacyDirKey-AbCdEfGhI
A_OLDTXT=1AliceOldTxtXXXXXXXXXXXXXXXXXXXXXX
A_ODD=1AliceOddNamesFolderXXXXXXXXXXXXXX
A_QUOTES=1AliceQuotesTxtXXXXXXXXXXXXXXXXXX
A_UNICODE=1AliceUnicodePdfXXXXXXXXXXXXXXXXX
A_NEWLINE=1AliceNewlinePdfXXXXXXXXXXXXXXXXX
A_DOLLAR=1AliceDollarNameXXXXXXXXXXXXXXXXX
A_DASH=1AliceDashLeadingXXXXXXXXXXXXXXXXX
# Shortcuts: own (shortcut) ids and targets
A_SC_PLAN=1AliceShortcutToPlanXXXXXXXXXXXXXX
A_SC_PROJ=1AliceShortcutToProjectsXXXXXXXXXX
A_TOP=1AliceSharedThingTopXXXXXXXXXXXXXX       # .shortcut-targets-by-id/<A_TOP>/
A_INSIDE=1AliceInsidePdfXXXXXXXXXXXXXXXXXX
A_SC_THING=1AliceShortcutToThingXXXXXXXXXXXXX
A_SC_INSIDE=1AliceShortcutToInsideXXXXXXXXXXXX
A_SC_BROKEN=1AliceBrokenShortcutXXXXXXXXXXXXXX
A_SC_STANDIN_DOC=1AliceStandinDocShortcutXXXXXXXXXX
A_STANDIN_DOC_TARGET=1AliceStandinDocTargetXXXXXXXXXXXXXXXXXXXXXXX
A_SC_STANDIN_PDF=1AliceStandinPdfShortcutXXXXXXXXXX
A_STANDIN_PDF_TARGET=1AliceStandinPdfTargetXXXXXXXXXXXX
A_SC_STANDIN_OLD=1AliceStandinOldShortcutXXXXXXXXXX
A_STANDIN_OLD_TARGET=0BAliceStandinOldTargetXXXXX
A_STANDIN_OLD_KEY=0-StandinOldKey_AbCdEfGh
A_SC_STANDIN_REMOTE=1AliceStandinRemoteShortcutXXXXXXXXXX
A_STANDIN_REMOTE_TARGET=0BAliceStandinRemoteTargetXXXXX
A_STANDIN_REMOTE_KEY=0-StandinRemoteKeyAbCdEf
A_HIDDEN_PARENT=1AliceInvisibleParentXXXXXXXXXXXXX  # DB only, not on disk
A_SC_TEAM=1AliceShortcutBackToTeamXXXXXXXXX
# Shared drive
A_TEAM=0ATeamAlphaDriveUk9PVA
A_SPECS=1AliceSpecsDocXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
A_ASSETS=1AliceAssetsFolderXXXXXXXXXXXXXXX
A_LOGO=1AliceLogoPngXXXXXXXXXXXXXXXXXXXXX
# Other computers
A_COMPUTER=1AliceStudioMacFolderXXXXXXXXXXXX
# Hidden
A_TRASHED=1AliceTrashedPdfXXXXXXXXXXXXXXXXX
A_TMPITEM=1AliceTmpItemXXXXXXXXXXXXXXXXXXXX

# bob@gmail.com ---------------------------------------------------------------
B_MYDRIVE=0ABobMyDriveRootUk9PVA
B_NOTES=1BobNotesDocXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
B_PHOTOS=1BobPhotosFolderXXXXXXXXXXXXXXXXX
B_BEACH=1BobBeachJpgXXXXXXXXXXXXXXXXXXXXX
B_OLDSCAN=0BBobOldScanPdfXXXXXXXXXXXXX

# carol@umich.edu ---------------------------------------------------------------
C_MYDRIVE=0ACarolMyDriveRootUk9PV
C_SYLLABUS=1CarolSyllabusDocXXXXXXXXXXXXXXXXXXXXXXXXXXX

# dave@umich.edu ----------------------------------------------------------------
D_MYDRIVE=0ADaveMyDriveRootUk9PVA
D_GRADES=1DaveGradesSheetXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Stray file outside any Drive mount that still carries an id (cp keeps xattrs)
STRAY_ID=$A_REPORT

# Names with special characters -------------------------------------------------
NAME_QUOTES="Q3 \"final\" 'v2' notes.txt"
# NFC on disk: e-acute U+00E9, CJK, check mark
NAME_UNICODE="$(printf 'R\303\251sum\303\251 \346\227\245\346\234\254 \342\234\223.pdf')"
# the same name in NFD (e + U+0301), as the DB may store it
NAME_UNICODE_NFD="$(printf 'Re\314\201sume\314\201 \346\227\245\346\234\254 \342\234\223.pdf')"
NAME_NEWLINE="$(printf 'Line\nBreak.pdf')"
# shellcheck disable=SC2016  # a literal $(...) and backticks, on purpose
NAME_DOLLAR='$(touch pwned) `touch pwned2`.txt'
NAME_DASH="-dash-leading.pdf"
NAME_ICON="$(printf 'Icon\r')"

# Chrome profile directories used by the fixture
CHROME_PROFILE_A="Profile 1"   # primary alice (user_name Alice@Example.com)
CHROME_PROFILE_C="Profile 2"   # carol is a SECONDARY account here
CHROME_PROFILE_B="Profile 3"   # primary bob@googlemail.com (== bob@gmail.com)
