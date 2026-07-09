# Prop Builder Final Test Checklist

## Startup
- [ ] Flutter app launches without errors
- [ ] FastAPI backend health shows Online
- [ ] Prop Builder loads presets
- [ ] Build history loads
- [ ] Strategy panel loads
- [ ] Watchlist count loads
- [ ] Active Slip restores after restart

## Builder Filters
- [ ] Same Sport mode works
- [ ] Mixed Sports mode works
- [ ] Sports filters work
- [ ] Prop-site filters work
- [ ] Market filters work
- [ ] Over-only works
- [ ] Under-only works
- [ ] Edge slider works
- [ ] Confidence slider works
- [ ] Leg count works
- [ ] Same-game toggle works

## Risk Modes
- [ ] Safe applies correct defaults
- [ ] Balanced applies correct defaults
- [ ] Aggressive applies correct defaults
- [ ] Risk mode is saved in presets
- [ ] Risk mode appears in history

## Build Results
- [ ] Generated legs contain no duplicates
- [ ] Partial builds show a warning
- [ ] No-result builds show useful actions
- [ ] Player image fallback works
- [ ] Edge and confidence display correctly
- [ ] Source and matchup display correctly

## Correlation Guard
- [ ] Maximum props per player works
- [ ] Maximum props per game works
- [ ] Maximum props per team works
- [ ] Guard Off allows concentrated builds
- [ ] Correlation warnings display

## Pick Actions
- [ ] Add and remove selection works
- [ ] Replace works
- [ ] Lock works
- [ ] Regenerate unlocked works
- [ ] Drag reorder works
- [ ] Notes are preserved
- [ ] Labels are preserved
- [ ] Explanation panel works

## Strategy
- [ ] Best sport displays
- [ ] Best site displays
- [ ] Best market displays
- [ ] Recommended settings apply
- [ ] Small sample warnings display

## Line Movement
- [ ] Manual line check works
- [ ] Auto line check works
- [ ] Better line displays
- [ ] Worse line displays
- [ ] Unavailable line displays
- [ ] Line alerts are deduplicated
- [ ] Alert click scrolls to prop

## Watchlist
- [ ] Add to Watchlist works
- [ ] Watchlist persists after restart
- [ ] Watchlist line check works
- [ ] Lock watched prop works
- [ ] Replace watched prop works
- [ ] Notes persist
- [ ] Add watched prop to Active Slip works

## Active Slip
- [ ] Selected props transfer in order
- [ ] Duplicate props are skipped
- [ ] Notes and labels transfer
- [ ] Line movement transfers
- [ ] Grading status transfers
- [ ] Active Slip persists after restart
- [ ] Reorder persists
- [ ] Remove and Clear work

## Export
- [ ] Copy as text works
- [ ] Save PNG works
- [ ] Save PDF works
- [ ] Print dialog opens
- [ ] Pick order is preserved
- [ ] Notes and labels appear

## History and Performance
- [ ] Build history saves correctly
- [ ] History restores builds
- [ ] Grading updates history
- [ ] Sport performance is accurate
- [ ] Site performance is accurate
- [ ] Market performance is accurate
- [ ] Date filters work

## Error Handling
- [ ] Backend-offline message works
- [ ] Provider timeout message works
- [ ] Rate-limit message works
- [ ] Invalid filter validation works
- [ ] Empty states appear correctly
