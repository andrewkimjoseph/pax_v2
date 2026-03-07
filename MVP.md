# Pax - Comprehensive MVP Specification

## Executive Summary

**Pax** is a mobile-first micro-task and rewards platform that connects researchers/organizations with participants who complete surveys and tasks in exchange for cryptocurrency rewards. The platform features identity verification, multi-currency wallet management, achievement gamification, and seamless withdrawal to external crypto wallets.

**Pax V2** introduces an improved wallet and rewards system: participants can have a **Pax Wallet** (EOA + smart account) with client-side key custody backed by Google Drive, gas sponsored via Canvassing contracts, and rewards/achievements paid through the **CanvassingRewarder** contract. V1 users (legacy proxy contract) continue to be supported; V1 users may see an upgrade path to V2 when the feature flag is enabled.

---

## Core Concept

Pax enables organizations ("Task Masters") to create micro-tasks (primarily surveys) that verified participants complete to earn cryptocurrency tokens. The platform ensures only real, verified humans participate through face verification integration with GoodDollar's identity system, preventing bots and fraud.

**V2:** New users typically onboard as V2 and create a Pax Wallet (no contract deployment). Rewards and achievements for V2 are distributed via the CanvassingRewarder contract to the participant's smart account. V1 (legacy) users use a server-managed proxy contract and existing flows until they upgrade.

---

## User Personas

### 1. Participant (Primary User)
- Signs up via Google authentication
- Completes profile (country, gender, date of birth)
- Verifies identity through connected wallet's face verification
- Browses and completes available tasks
- Earns cryptocurrency rewards
- Withdraws earnings to connected wallets
- Earns achievements for milestones

### 2. Task Master (Admin/Organization)
- Creates and publishes tasks
- Sets task parameters (reward amount, target participants, deadline)
- Funds task reward pools
- Reviews task completions

---

## Data Models

### Participant
```
- id: string (unique identifier)
- displayName: string (from Google auth)
- emailAddress: string (from Google auth)
- phoneNumber: string (optional)
- gender: enum ["Male", "Female"]
- country: string (country name)
- dateOfBirth: timestamp
- profilePictureURI: string (from Google auth)
- goodDollarIdentityTimeLastAuthenticated: timestamp
- goodDollarIdentityExpiryDate: timestamp
- accountType: string ("v1" | "v2") — V1 = legacy proxy contract; V2 = Pax Wallet / smart account
- onboardingType: string | null ("v1_legacy" | "v2_native" | "mixed" | null) — set after onboarding questionnaire
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Task
```
- id: string (unique identifier)
- taskMasterId: string (reference to creator)
- title: string
- type: enum ["checkOutApp", "fillAForm", "doVideoInterview"]
- category: string (default: "General")
- estimatedTimeOfCompletionInMinutes: number
- deadline: timestamp
- targetNumberOfParticipants: number
- link: string (URL to task/survey)
- levelOfDifficulty: string
- managerContractAddress: string (blockchain contract)
- rewardAmountPerParticipant: number
- rewardCurrencyId: number (1=GoodDollar, 2=CeloDollar, 3=USDT, 4=USDC)
- isAvailable: boolean
- isTest: boolean
- feedback: string
- paymentTerms: string
- instructions: string (multi-line)
- targetCountry: string ("ALL" or comma-separated country codes)
- numberOfCooldownHours: number (wait time before re-participation)
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Task Completion
```
- id: string
- taskId: string (reference)
- screeningId: string (reference)
- participantId: string (reference)
- timeCompleted: timestamp
- timeCreated: timestamp
- timeUpdated: timestamp
- isValid: boolean (indicates if submission is valid for reward)
```

### Screening
```
- id: string
- taskId: string (reference)
- participantId: string (reference)
- signature: string (cryptographic signature)
- nonce: string
- txnHash: string (blockchain transaction hash)
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Reward
```
- id: string
- participantId: string (reference)
- taskId: string (reference)
- screeningId: string (reference)
- taskCompletionId: string (reference)
- signature: string
- amountReceived: number
- rewardCurrencyId: number
- txnHash: string (blockchain transaction)
- isPaidOutToPaxAccount: boolean
- timePaidOut: timestamp
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Pax Account (User's Blockchain Wallet)

**V1 (Legacy):** Server-managed proxy contract. Identified by `contractAddress != null`.
**V2:** No proxy contract; user has EOA + smart account. Identified by `contractAddress == null && eoWalletAddress != null`. Payout address for V2 is `smartAccountWalletAddress`.

```
- id: string (same as participantId)
- contractAddress: string | null (V1 only; proxy contract address)
- contractCreationTxnHash: string | null (V1 only)
- serverWalletId: string | null (V1 server wallet)
- serverWalletAddress: string | null (V1 server wallet address)
- smartAccountWalletAddress: string | null (V2 smart account; payout address for V2)
- eoWalletAddress: string | null (V2 EOA address)
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Pax Wallet (V2 Only — in-app wallet document)

Stores the V2 user's EOA and smart account addresses. Backed by client-side encrypted key (e.g. Google Drive). Balances are read from chain for the EOA; rewards are sent to the smart account.

```
- id: string (document ID in pax_wallets collection)
- participantId: string (reference)
- eoAddress: string (EOA address)
- smartAccountAddress: string (smart account contract address)
- logTxnHash: string | null (optional onboarding log)
- logTimeCreated: timestamp | null
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Withdrawal Method (Payment Method)
```
- id: string
- predefinedId: number (1=MiniPay, 2=GoodWallet)
- participantId: string (reference)
- paxAccountId: string (reference)
- name: string ("MiniPay" or "GoodWallet")
- walletAddress: string (blockchain address)
- txnHash: string
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Withdrawal
```
- id: string
- participantId: string (reference)
- paymentMethodId: string (reference)
- amountTakenOut: number
- rewardCurrencyId: number
- txnHash: string
- timeRequested: timestamp
- timeCreated: timestamp
- timeUpdated: timestamp
```

### Achievement
```
- id: string
- participantId: string (reference)
- name: string (achievement type)
- tasksCompleted: number
- tasksNeededForCompletion: number
- timeCreated: timestamp
- timeCompleted: timestamp
- timeClaimed: timestamp
- amountEarned: number
- txnHash: string (reward transaction)
```

### FCM Token (Push Notifications)
```
- id: string
- participantId: string (reference)
- token: string (Firebase Cloud Messaging token)
- timeCreated: timestamp
- timeUpdated: timestamp
```

---

## Achievement System

### Achievement Types & Rewards

| Achievement Name | Goal | Reward (G$) |
|-----------------|------|-------------|
| Payout Connector | Connect first withdrawal method | 500 |
| Verified Human | Complete face verification | 500 |
| Profile Perfectionist | Fill country, gender, DOB | 400 |
| Task Starter | Complete 1 task | 100 |
| Task Expert | Complete 10 tasks | 1000 |
| Double Payout Connector | Connect 2 withdrawal methods | 500 |
| Triple Payout Connector | Connect 3 withdrawal methods | 500 |

### Achievement States
- **In Progress**: User is working toward the goal
- **Earned**: Goal completed, reward available to claim
- **Claimed**: Reward has been claimed and transferred

---

## Currency System

### Supported Currencies
1. **Good Dollar (G$)** - ID: 1 - Primary reward currency
2. **Celo Dollar (cUSD)** - ID: 2
3. **Tether USD (USDT)** - ID: 3
4. **USD Coin (USDC)** - ID: 4

### Currency Features
- Users can view balance in any supported currency
- Currency selection persists across sessions
- All currencies are ERC-20 compatible tokens on Celo blockchain

---

## Application Routes & Navigation

### Route Structure

```
/onboarding                              - Welcome screens (3 pages) + Sign in
/onboarding-questionnaire                - V2: GoodDollar usage + wallet access questions → create-v2-wallet | withdrawal-methods | home
/loading                                 - Resolves account type and redirects (e.g. to questionnaire, create-v2-wallet, home, v2-web-blocked)
/home                                    - Main hub with tabs (tab set depends on V1 vs V2)
  V1 tabs: Home (Dashboard, Tasks, Achievements) | Activity | Account
  V2 tabs: Home (Dashboard, Tasks, Achievements) | Wallet (Pax Wallet) | Apps (Miniapps) | Activity | Account

/create-v2-wallet                        - V2 wallet creation (Drive backup, EOA + smart account, register Pax Wallet as withdrawal method)
/pax-wallet                              - V2: Pax Wallet balance card + address (embedded in Wallet tab for V2)
/check-v2-eligibility                    - V1: Check if user can upgrade to V2
/v2-web-blocked                          - Shown when V2 user tries to use web app (must use mobile)

/wallet                                  - Balance view + withdrawal methods (V1; V2 uses Wallet tab + Pax Wallet)
/wallet/withdraw                         - Enter withdrawal amount
/wallet/withdraw/select-wallet           - Select withdrawal destination
/wallet/withdraw/select-wallet/review    - Confirm withdrawal

/tasks/task-summary                      - Task details before starting
/tasks/check-out-app                     - WebView for app check tasks
/tasks/fill-a-form                       - WebView for survey tasks

/claim-reward                            - Claim earned task reward

/withdrawal-methods                      - Manage connected wallets (V1 primary; V2 shows Pax Wallet card + MiniPay/GoodWallet when verified)
/withdrawal-methods/minipay-connection   - Connect MiniPay wallet
/withdrawal-methods/minipay-connection/copy-wallet-address
/withdrawal-methods/good-wallet-connection    - Connect GoodWallet
/withdrawal-methods/good-wallet-connection/copy-wallet-address

/complete-gooddollar-face-verification   - Face verification (V2: registers Pax Wallet after verification)
/complete-profile                        - Complete profile (country, gender, DOB)

/profile                                 - Edit profile details
/account-and-security                    - Account settings, delete account
/activity                                - Transaction history
/help-and-support                        - Help options
/help-and-support/faq                    - Frequently asked questions
/help-and-support/contact-support        - Contact form

/miniapp-webview                         - V2: WebView for miniapp or custom URL
/webview-converter                       - Converter WebView

/canvassing-x-gooddollar                 - Partnership info page
/report-page                             - View published research reports
/reports                                 - Reports list
/notifications                           - Notification center
```

---

## Feature Specifications

### 1. Onboarding Flow

**Screens:**
1. **Welcome Screen 1**: "Earn as you share your opinions" - Introduction
2. **Welcome Screen 2**: "We value your voice. We pay for your opinion." - Value proposition
3. **Welcome Screen 3**: "Sign in with Google" - Authentication

**Post sign-in (V2):**
4. **Onboarding Questionnaire** ("Let's get to know you"): Asks whether user has used G$ or UBI payouts before (Yes / Heard of it / No, first time). If "Yes", asks "Still have access to that wallet?" (Yes / No). Outcomes:
   - **v2_native** (e.g. "No, first time") → Create V2 wallet flow
   - **v1_legacy** (Yes + can access wallet) → Withdrawal methods (legacy)
   - **mixed** → Create V2 wallet flow
5. **Create V2 Wallet** (when v2_native or mixed): Google Drive scopes for backup → create EOA + encrypted key → create `pax_wallets` doc → create smart account via backend → update Participant `accountType: "v2"` → register "PaxWallet" as withdrawal method → redirect to complete profile or home.

**Functionality:**
- Swipeable page carousel with dot indicators (welcome)
- Skip button (jumps to last page)
- Continue button (advances one page)
- Google Sign-In integration
- Automatic user creation in database on first sign-in (with default `accountType: "v1"`, `onboardingType: null`)
- Progress indicators (3 dots)
- V1 users may see **V2 availability banner** (when `is_v2_upgrade_available` is true) linking to Check V2 Eligibility

---

### 2. Dashboard

**Components:**
- Current Balance Card (shows selected currency balance) — V1 uses pax_account balances; V2 home tab shows dashboard balance card
- **V2:** Bottom nav includes **Wallet** (Pax Wallet view) and **Apps** (Miniapps) tabs
- Social Links Carousel (X, Telegram, WhatsApp links)
- Image Carousel (5 rotating promotional images)
- Published Reports Section (links to research reports)
- **V2:** V1 users may see "V2 is Available!" banner (when flag enabled) → Check V2 Eligibility

**Balance Card Features:**
- Currency selector dropdown (4 currencies)
- Balance refresh button (5-minute cooldown for V1; V2 Pax Wallet has its own refresh)
- Wallet/Withdraw button
- Loading skeleton during fetch

---

### 3. Tasks System

**Task List View:**
- Real-time list of available tasks
- Tasks filtered by participant's country
- Shows task count badge in tab
- Empty state with Lottie animation when no tasks
- Task cards showing: title, reward amount, difficulty, time estimate

**Task Card Information:**
- Task title
- Reward amount with currency icon
- Estimated completion time
- Difficulty level
- Action type (Check Out App / Fill A Form)
- Category badge
- Deadline indicator

**Task Summary View:**
- Full task image
- Detailed task information card
- Instructions preview (first 2 lines, expandable)
- "Continue with task" button

**Task Execution Flow:**
1. User clicks task from list → Task Summary
2. System checks: withdrawal method connected + profile complete
3. If incomplete → Dialog prompting to add withdrawal method
4. System checks task manager contract has sufficient balance
5. Screening process begins (blockchain verification)
6. On success → Navigate to task WebView
7. Task loads in embedded WebView
8. User completes task (survey/app checkout)
9. Task completion recorded
10. User redirected to claim reward

**Task Types:**
- **Check Out App**: Visit and interact with a web/mobile app
- **Fill A Form**: Complete a survey form

**Cooldown System:**
- Tasks can have cooldown periods (hours)
- Users must wait before re-participating
- Countdown timer shows remaining wait time
- Button disabled during cooldown

**Screening Process:**
- Verifies participant eligibility
- Creates blockchain transaction
- Generates cryptographic signature
- Records screening in database

---

### 4. Reward Claiming

**Claim Reward View:**
- Task completion confirmation graphic
- Amount earned display
- Task completion ID (copyable)
- Cooldown status indicator (if applicable)
- Invalid submission notice (if marked invalid)

**Claim States:**
- **Not Completed**: "Complete Task" button → Returns to tasks
- **Cooldown Active**: Shows countdown timer, button disabled
- **Ready to Claim**: "Claim Reward" button active
- **Claimed**: Button shows "Claimed", disabled
- **Invalid**: Shows error message, cannot claim

**Claim Process:**
1. User taps "Claim Reward"
2. Loading dialog appears
3. Backend processes reward
4. Blockchain transaction executed
5. Success dialog with confirmation
6. User redirected to home

---

### 5. Achievements

**Achievement View:**
- Partnership banner (Canvassing x GoodDollar)
- Filter tabs: All, In Progress, Earned, Claimed
- Achievement cards list

**Achievement Card:**
- Achievement icon (SVG)
- Achievement name
- Goal description
- Progress indicator (X/Y tasks)
- Reward amount
- Status badge
- Claim button (when earned)

**Achievement Claim Process:**
1. User taps "Claim" on earned achievement
2. Loading dialog
3. Backend verifies eligibility
4. Blockchain reward transaction
5. Success confirmation
6. Achievement status updated to "Claimed"

---

### 6. Wallet & Withdrawals

**Wallet View:**
- **V1:** Current balance card with currency selector, refresh balance button, Available Withdrawal Methods (MiniPay, GoodWallet).
- **V2:** Dedicated **Wallet** tab shows **Pax Wallet** view: balance card (G$ hero + cUSD/USDT pills), wallet address, "Check G$ exchange rate" link, refresh. Withdrawal methods screen shows **Pax Wallet** card first (connected once wallet created); MiniPay and GoodWallet cards shown only after Pax Wallet address is verified (GoodDollar identity). V2 withdrawal uses encrypted params (encryptedPrivateKey, sessionKey, eoWalletAddress) passed to backend.

**Withdrawal Flow:**
1. Select currency to withdraw
2. Enter amount (validates: >0, ≤ balance, max 2 decimals)
3. Select destination wallet (MiniPay or GoodWallet; V2 also has Pax Wallet as source)
4. Review summary (amount, fees, destination)
5. Confirm withdrawal
6. Processing dialog (V2: backend decrypts key, executes via Canvassing contracts as needed)
7. Blockchain transaction
8. Success confirmation

**Withdrawal Amount Validation:**
- Must be greater than 0
- Cannot exceed available balance
- Maximum 2 decimal places
- Real-time validation feedback

---

### 6a. Pax Wallet (V2 Only)

**Pax Wallet** is the in-app wallet for V2 users: an EOA (key encrypted and backed up to Google Drive) plus a smart account (gas-sponsored). Rewards and achievement payouts are sent to the smart account; balances are read from the EOA for display (G$, cUSD, USDT, USDC). Cached in local DB for quick load; refresh fetches from chain.

**Creation (Create V2 Wallet flow):**
- Google Sign-In with Drive scope for backup
- Generate EOA and encrypt private key with session key (e.g. Google account id)
- Create `pax_wallets` document with `eoAddress`; backend `createSmartAccountForPaxV2User` creates smart account and returns address; app updates doc with `smartAccountAddress`
- Register "PaxWallet" as a withdrawal method (payment_methods)
- Participant `accountType` set to `"v2"`; pax_accounts doc has `eoWalletAddress` and `smartAccountWalletAddress` (no `contractAddress`)

**Pax Wallet tab (V2):**
- Balance card with currency pills, address row, exchange link, refresh
- Face verification required for tasks/withdrawals; after verification, Pax Wallet EOA is whitelisted with GoodDollar Identity and MiniPay/GoodWallet options become available

**Web:** V2 users opening the app on web are redirected to `/v2-web-blocked` ("Your account uses Pax Wallet. Please sign in on the mobile app to continue.").

---

### 6b. Miniapps (V2 Only)

**Apps** tab is shown only for V2 users. If V2 user has not completed face verification, they see a prompt to verify identity before using PaxWallet apps.

**Features:**
- List of miniapps from Remote Config (`miniapps_config`: `are_miniapps_available` + `miniapps` array with id, name, title, imageURI, url, etc.)
- Optional "Open by URL" (custom dapp) when `is_custom_app_access_feature_available` is true — dialog to paste URL, then open in miniapp WebView
- Tapping a miniapp opens `/miniapp-webview` with the app URL; WebView can use `window.PaxWallet` (ethereum provider) for dapp interactions
- Converter WebView route (`/webview-converter`) for conversion flows

---

### 7. Withdrawal Methods Connection

**Supported Methods:**
1. **Pax Wallet** (V2 only) — In-app EOA + smart account; registered automatically when V2 wallet is created; shown as first card on withdrawal methods for V2.
2. **MiniPay** - Celo mobile wallet
3. **GoodWallet** - GoodDollar ecosystem wallet

**V2 behaviour:** For V2 users, MiniPay and GoodWallet cards are only shown when the Pax Wallet address is verified (GoodDollar Identity whitelist). Until then, only the Pax Wallet card is shown (and user is prompted to complete face verification for tasks/withdrawals).

**Connection Flow (Both Methods):**
1. User navigates to withdrawal methods
2. Taps on desired method card
3. Guide screens explain the process
4. User copies their Pax account address
5. User goes to external wallet app
6. User sends small amount to Pax address
7. System detects transaction
8. Wallet linked automatically
9. Confirmation shown

**Connection Verification:**
- System monitors blockchain for incoming transactions
- Extracts sender's wallet address
- Links wallet to user's Pax account
- Creates withdrawal method record

**Guide Steps (MiniPay):**
1. Download MiniPay if not installed
2. Open MiniPay
3. Copy your Pax receiving address
4. In MiniPay, tap Send
5. Paste Pax address
6. Send minimum amount
7. Wait for confirmation

---

### 8. Profile Management

**Profile View:**
- Profile picture (from Google, not editable)
- Display name (from Google, read-only)
- Email (from Google, read-only)
- Country (editable once, then locked)
- Gender (editable once, then locked)
- Date of Birth (editable once, then locked)

**Validation Rules:**
- Country: Required, select from list
- Gender: Required, Male/Female
- Date of Birth: Required, must be 18+ years old

**Profile Completion:**
- Users cannot start tasks without completing profile
- Profile fields lock after first save
- Triggers "Profile Perfectionist" achievement

---

### 9. Account & Security

**Options:**
- Delete Account (with confirmation flow)

**Account Deletion:**
- Requires confirmation
- Deletes all user data
- Signs out user
- Blockchain assets remain in user's connected wallets

---

### 10. Help & Support

**Help Options:**
- FAQ section
- Contact Support form

**FAQ Content:**
- Task frequency (weekly, typically Tuesdays)
- Task availability times (8:00 AM UTC)
- Face verification explanation
- Task capacity/rush situations
- Currency conversion guides
- Account ban information
- Achievement claiming hours

---

### 11. Notifications

**Push Notifications For:**
- New task available
- Reward claimed successfully
- Withdrawal completed
- Achievement unlocked
- Achievement ready to claim
- System announcements

**FCM Token Management:**
- Token registered on app launch
- Updated when token refreshes
- Associated with participant ID

---

### 12. Navigation Drawer

**Drawer Options:**
- Profile
- Wallet
- Activity (transaction history)
- Achievements
- Help & Support
- Account & Security
- Logout

---

## Backend Functions

### Cloud Functions

1. **createPrivyServerWallet**
   - Creates secure server-managed wallet for new users (V1)

2. **createPaxAccountV1Proxy**
   - Deploys smart contract account for user (V1)
   - Links withdrawal method

3. **addNonPrimaryWithdrawalMethodToPaxAccountV1Proxy**
   - Adds secondary withdrawal method to existing account (V1)

4. **createSmartAccountForPaxV2User** (V2)
   - Called by app after EOA and encrypted key are created
   - Decrypts private key with session key, creates smart account via Pimlico/permissionless (EntryPoint 0.7), writes smart account address to pax_accounts (and optionally pax_wallets)
   - Requires: encryptedPrivateKey, eoWalletAddress, sessionKey

5. **screenParticipantProxy**
   - Verifies participant eligibility for task
   - Creates screening record
   - Generates cryptographic signature

6. **markTaskCompletionAsComplete**
   - Marks task as completed after survey submission

7. **rewardParticipantProxy**
   - **V1:** Processes reward claim via legacy flow, executes blockchain reward transfer, records reward transaction.
   - **V2:** Uses CanvassingRewarder proxy: validates backend signature, decrypts participant key, submits reward claim to CanvassingRewarder contract (tokens to participant's smart account), records reward with bundle txn hash. Requires client to pass encryptedPrivateKey, sessionKey, eoWalletAddress.

8. **withdrawToPaymentMethod**
   - Processes withdrawal request (V1 or V2)
   - V2: accepts paymentMethodAddress and v2EncryptedParams (encryptedPrivateKey, sessionKey, eoWalletAddress) for signing and sending from EOA/smart account
   - Transfers tokens to external wallet, records withdrawal

9. **processAchievementClaim**
   - **V1:** Legacy achievement payout flow.
   - **V2:** Verifies achievement completion, decrypts key, submits claim to CanvassingRewarder proxy (achievement reward to smart account), updates achievement status. Requires eoWalletAddress, encryptedPrivateKey, sessionKey when V2.

10. **deleteParticipantOnRequest**
    - Handles GDPR deletion requests
    - Removes user data

11. **sendNotification**
    - Sends push notifications via FCM

12. **notifyPaxTotifierAboutNewUser**
    - Alerts admin bot about new registrations

### V2 Blockchain Contracts (Hardhat)

- **CanvassingTaskManager** — Screening and task state (e.g. has participant been screened for task).
- **CanvassingRewarder** — Holds ERC20 balances; distributes task and achievement rewards to participants' smart accounts based on backend-signed payloads; gated by TaskManager for task rewards and by signature for achievement rewards.
- **CanvassingWalletRegistry** — Registry for wallet/account linkage (as used by backend).
- **CanvassingGasSponsor** — Gas sponsorship for user operations (e.g. paymaster).

---

## Feature Flags (Remote Config)

| Flag Key | Purpose |
|----------|---------|
| areTasksAvailable | Enable/disable tasks tab |
| areAchievementsAvailable | Enable/disable achievements tab |
| isWalletAvailable | Enable/disable wallet access |
| isWithdrawalMethodConnectionAvailable | Enable/disable wallet connection |
| is_v2_upgrade_available | Show "V2 is Available!" banner to V1 users and allow Check V2 Eligibility flow |
| is_custom_app_access_feature_available | Show "Open by URL" (custom dapp) in Apps (Miniapps) view for V2 |
| are_miniapps_available | Enable miniapps list for V2 (inside miniapps_config) |

---

## Analytics Events

### Authentication
- signInWithGoogleTapped
- signOutTapped

### Navigation
- dashboardTapped
- tasksTapped
- achievementsTapped
- homeWalletTapped
- walletWithdrawTapped
- optionsTapped

### Task Flow
- taskCardTapped
- continueWithTaskTapped
- screeningStarted
- screeningFailed
- taskCompleted
- claimRewardTapped
- claimRewardComplete
- claimRewardFailed
- goHomeToCompleteTaskTapped

### Wallet
- refreshBalancesTapped
- continueWithdrawTapped
- withdrawalMethodConnectionTapped
- setUpWithdrawalMethodTapped

### V2 / Pax Wallet / Miniapps
- v2PaxWalletRouteVisited
- v2WalletCreationInitiated
- v2AvailabilityBannerShown
- v2UpgradeEligibilityChecked
- v2FaceVerificationPromptShown / v2FaceVerificationPromptTapped
- onboardingQuestionnaireCompleted (with onboardingType, usageAnswer, walletAccessAnswer)
- miniappTapped (miniapp_id, miniapp_name, miniapp_title, miniapp_url)
- customDappOpened (custom_dapp_url)

### Profile
- saveProfileChangesTapped

### Onboarding
- onboardingSkipTapped

---

## UI/UX Specifications

### Color Palette
- **Deep Purple**: Primary brand color (#5E4DB2)
- **Lilac**: Secondary accent
- **White**: Background
- **Light Grey**: Borders, dividers
- **Green**: Success states
- **Red**: Error states, badges
- **Orange to Pink Gradient**: Premium accents

### Design Patterns
- Card-based layouts
- Bottom navigation: **V1** — Home, Activity, Account; **V2** — Home, Wallet (Pax Wallet), Apps (Miniapps), Activity, Account
- Tab navigation in home (Dashboard, Tasks, Achievements)
- Pull-to-refresh on lists
- Skeleton loading states
- Toast notifications
- Modal dialogs for confirmations
- Bottom sheets for complex selections

### Typography
- Bold headers (28-32px)
- Section titles (20px)
- Body text (14-16px)
- Captions (12px)

---

## Security Considerations

### Authentication
- Google OAuth 2.0 only
- Session management via Firebase Auth
- Auto-logout on token expiration

### Data Protection
- Profile fields non-editable after first save
- Age verification (18+ requirement)
- Identity verification via GoodDollar

### Blockchain Security
- **V1:** Server-managed wallets (no private keys on client)
- **V2:** Client-side EOA key encrypted with session key (e.g. Google account id), backed up to Google Drive; backend decrypts only when processing reward claim or withdrawal (encryptedPrivateKey + sessionKey + eoWalletAddress). Smart account creation and reward distribution via CanvassingRewarder; gas sponsored.
- Cryptographic signatures for all transactions
- Transaction verification before reward distribution

### Privacy
- Account deletion capability
- Minimal data collection
- Clear privacy policy

---

## Task Availability Rules

1. Tasks have limited participant slots
2. First-come, first-served basis
3. Tasks expire after deadline
4. Country-targeted tasks only show to eligible users
5. Tasks with cooldowns prevent repeat participation
6. Invalid submissions cannot claim rewards

---

## Error Handling

### User-Facing Errors
- Network connectivity issues
- Insufficient balance for withdrawal
- Task manager insufficient funds
- Screening failures
- Claim failures
- Invalid submissions

### Error Messages
- Clear, actionable language
- Contact support suggestions
- Retry options where applicable

---

## Platform Requirements

### Mobile Support
- iOS
- Android
- Web (responsive; V2 users are blocked on web with message to use mobile app)

### Minimum Requirements
- Internet connection
- Google account
- Age 18+
- Supported country

---

## Integration Points

### External Services
- Google Sign-In (Authentication; V2 also uses Drive scope for wallet backup)
- GoodDollar (Identity verification, G$ token; V2: direct RPC for whitelist check)
- MiniPay (Celo wallet)
- GoodWallet (GoodDollar wallet)
- Firebase (Database, Auth, Functions, Messaging, Analytics, Remote Config)
- Celo Blockchain (Smart contracts, token transfers)
- **V2:** Pimlico (bundler/paymaster API for smart account creation and gas sponsorship)
- **V2:** permissionless / viem (EntryPoint 0.7, simple smart account)

### Social Links
- X (Twitter): Follow for updates
- Telegram: Community group
- WhatsApp: Community group

---

## Appendix: FAQ Content

1. **Task Frequency**: Once weekly (4 tasks/month), dependent on researchers
2. **Task Time**: 8:00 AM UTC / 9:00 AM WAT / 10:00 AM CAT / 11:00 AM EAT
3. **Task Day**: Tuesdays (PaxDay)
4. **Pax V2 / What's new**: Pax V2 is the latest version with an improved wallet and rewards system. Users get the same tasks and rewards; the in-app wallet is created differently (Pax Wallet: EOA + smart account, key backed up to Google Drive) and gas is handled via Canvassing contracts. No action needed from existing users—use the app as usual. New users typically onboard as V2 and create a Pax Wallet.
5. **Face Verification**: Required for fraud prevention via GoodDollar Identity
6. **Task Availability**: First-come-first-served, high volume causes quick closure
7. **G$ to cUSD Conversion**: Guide available via Medium article
8. **Task Types**: Currently surveys only, more coming
9. **Questions per Task**: 10-15 questions
10. **Slot Booking**: Grants immediate access to task
11. **Account Ban**: Disabled accounts cannot do tasks or withdraw
12. **Notifications**: Why we ask after sign-in (new tasks, rewards, withdrawals; optional)
13. **Achievement Claiming Hours**: Daily 8AM-3PM UTC window

---

## Success Metrics

- User registration rate
- Task completion rate
- Average time to complete task
- Reward claim rate
- Achievement completion rate
- Withdrawal frequency
- User retention (weekly active users)
- Average earnings per user

---

*This MVP specification provides a complete blueprint for recreating the Pax platform. All systems, models, user flows, and functionalities are documented to enable accurate reproduction of the application's core features.*


