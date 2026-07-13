// index.ts
//
// Entry point Firebase Functions deploy actually loads (functions/package.json
// "main": "lib/index.js"). Without this file re-exporting them, fetchGdeltArticles
// and crisisClassifier compile and type-check fine but `firebase deploy --only
// functions` has nothing to discover -- lib/index.js wouldn't exist at all, so
// the CLI's require() of the main entry fails and zero functions get deployed.

export { fetchGdeltArticles } from "./fetchGdeltArticles";
export { crisisClassifier } from "./crisisClassifier";
