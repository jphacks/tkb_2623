import { createRecommendationHandler } from "./recommendation.ts";

Deno.serve(createRecommendationHandler({
  env: (name) => Deno.env.get(name),
}));
