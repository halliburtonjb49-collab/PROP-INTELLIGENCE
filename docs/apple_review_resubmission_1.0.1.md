# PI Prop Intelligence - App Review Resubmission Notes

Use this document for the App Review Information notes and the Resolution
Center response for build 1.0.1 (8). Replace every bracketed value with tested,
current information before submitting.

## Resolution Center response

Hello App Review Team,

Thank you for the opportunity to provide additional information about PI Prop
Intelligence.

### 1. Physical-device recording

A recording captured on a physical Apple device running the latest available
operating system is attached. The recording begins by launching PI Prop
Intelligence and demonstrates registration, login, subscription access,
purchase restoration, account deletion, the Market Board, sport/provider/
category filtering, detailed research, scoreboard, tracked research slips,
Prop Chat, reporting a message, and blocking a user.

### 2. Tested devices

- [IPHONE MODEL] running iOS [VERSION]
- [IPAD MODEL, IF SUPPORTED/TESTED] running iPadOS [VERSION]

Testing covered authentication, Apple In-App Purchase, purchase restoration,
account deletion, live-data loading, filters, chat moderation, tracked research
selections, and recovery from an interrupted network connection.

### 3. Functions, audience, and value

PI Prop Intelligence is an independent sports-data research and organization
application for adult sports enthusiasts and analysts. It consolidates
sports-prop market information from supported data providers, organizes it by
sport, provider, and category, and presents research indicators for comparing
available market information.

The app does not accept wagers, facilitate wagering transactions, hold funds,
or connect users to a sportsbook to place bets. A research selection or tracked
research slip is an organizational record inside the application and has no
monetary value.

### 4. Setup and feature access

Launch the app and select Log In.

- Demo email: [DEMO EMAIL]
- Demo password: [DEMO PASSWORD]

The demo account must have access to every customer-facing feature under
review. No sample files or external hardware are required.

Primary navigation:

- Props opens the Market Board.
- The top navigation selects a sport.
- Sites and Categories filter the displayed research.
- View Research opens the detailed explanation for a card.
- ML Games opens moneyline game research.
- Watch displays tracked research slips.
- Prop Chat provides general and sport rooms.
- A message's action menu provides Report Message and Block User.
- Account provides Restore Purchases, Manage Subscription, Terms, Privacy, and
  Delete Account.

### 5. External services

- Supabase: authentication, account records, synchronized data, and chat.
- Sign in with Apple and Google: optional account authentication.
- RevenueCat and Apple In-App Purchase: subscription entitlement management.
- OneSignal: optional notifications.
- Render: secured application API hosting.
- Vercel: web application delivery.
- Licensed sports-data APIs: schedules, scores, player-prop market information,
  and supporting sports data.

Provider names identify the source of displayed market data. PI Prop
Intelligence does not facilitate transactions with those providers.

### 6. Regional differences

The application is currently distributed in the United States and Canada.
Core functionality is consistent across supported regions. Live sports content
varies based on league schedules, provider inventory, and data availability.
The app does not enable wagering in any region.

### 7. Regulated services and third-party material

PI Prop Intelligence is a sports-data research product, not a sportsbook,
gambling operator, financial institution, or wagering intermediary. It does
not accept bets, deposits, withdrawals, or financial stakes. Sports and market
information is obtained through contracted data-service subscriptions and
APIs. Provider and league names are used descriptively to identify sports,
events, and data sources.

### 8. In-App Purchase

The app offers auto-renewable subscriptions that unlock research tools and
continuously updated sports information. Before purchase, the subscription
screen displays the plan, duration, price, trial language where applicable,
included access, renewal disclosure, Restore Purchases, Terms of Use, and
Privacy Policy.

Navigation: launch the app, sign in, and select Account or any locked feature
to open the plan screen. Existing customers can select Restore Purchases.
Subscription management is available from Account > Manage Subscription.

## Physical-device recording checklist

Record one continuous video on a physical Apple device. Do not use a simulator,
marketing edit, music, or a staged mockup.

1. Show the device home screen and launch PI Prop Intelligence.
2. Show account registration or explain that the supplied demo account is used.
3. Log in with the reviewer demo account.
4. Open the plan screen and show product title, duration, price, trial language,
   renewal disclosure, Terms, Privacy, and Restore Purchases.
5. Show the Market Board loading real content.
6. Select a sport, provider, and category.
7. Open View Research.
8. Add and remove a research selection.
9. Open ML Games and the scoreboard.
10. Open Watch and show a tracked research slip.
11. Open Prop Chat, open a message action menu, select Report Message, and show
    the Block User option. A test message/account may be used.
12. Open Account and show Manage Subscription and Delete Account. Do not delete
    the reviewer account during the recording.
13. If a notification permission prompt appears, show it and explain that
    notifications are optional.

Keep the production backend and demo account active for the full review period.
