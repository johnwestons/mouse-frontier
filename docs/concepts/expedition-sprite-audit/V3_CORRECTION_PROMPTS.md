# Targeted walk corrections, v3 candidates

Mode: built-in ImageGen edit, September 10, 2026. Inputs: original action atlas, v2 walk atlas, and runtime-extracted original neutral idle. Source versions remain untouched. Candidates are not approved while phase errors remain.

## Bandit

Use case: precise-object-edit.
Input image1 is the ORIGINAL six-action identity reference. Image2 is the EIGHT-FRAME WALK EDIT TARGET. Image3 is the original neutral silhouette/camera anchor.
Repair ONLY the incorrect limb identity and walking sequence in image2, matching image1/image3 identity. Asset type: production 2D pixel-painted game walking sprite atlas, 4 columns by 2 rows, exactly eight complete individual frames in row-major order. Keep every sprite entirely inside its own equal cell with generous transparent edge margin, a common character scale and foot baseline, fixed camera and fixed light. Genuine transparent background with alpha; no drawn checker pattern, no white background, no ground shadows, no labels, text or grid borders. Preserve the supplied character's crisp dark outline, warm cloth/fur palette, glossy black parasite, cyan fissures and yellow infected eye. This must be eight different mechanically plausible consecutive walking poses, not repeated poses, not unrelated action poses.
The bandit keeps the SAME slightly elevated three-quarter view, facing and walking screen-RIGHT in every cell. Keep hood, orange ear/face, green scarf, backpack/bedroll, patched trousers, long red tail exactly the same character.
Identity lock across all eight cells: the normal arm always ends in the orange hand; the infected arm always ends in the long glossy BLACK claw, never an orange fist. The healthy leg always ends in the brown wrapped BOOT. The other leg, starting below its trouser cuff, is always the cyan-veined BLACK sludge leg/foot, without a brown boot. These two legs remain attached to their correct hips when they cross. Do NOT swap those materials or which hand is infected in frames5-8.
Eight-pose physical sequence facing RIGHT:
1 top-left: HEALTHY BROWN BOOT reaches forward to the right for contact; BLACK FOOT is behind to the left.
2: brown boot loads flat on ground; black heel lifts behind.
3: brown boot is planted under body; black swinging foot PASSES beneath hips, knees close.
4: brown boot supports from behind; BLACK knee and foot lift forward to right, preparing its contact.
5 bottom-left: BLACK FOOT contacts ground FORWARD to right; healthy brown boot is now BEHIND to left. This MUST be the opposite-leg contact from frame1.
6: black foot loads flat in front; healthy boot's heel rises behind, both arms still preserve their identities.
7: black foot is planted beneath body; HEALTHY BROWN BOOT passes beneath hips.
8 bottom-right: black leg supports from behind; HEALTHY BROWN BOOT knee lifts forward to right, preparing frame1.
Natural counter-swing of the same two attached arms; restrained torso bob. Do not mirror row2, do not repeat row1's planted leg. No cropping. Return only the repaired eight-frame walk atlas.

## Buried Host

Use case: precise-object-edit.
Input image1 is the ORIGINAL six-action identity reference. Image2 is the EIGHT-FRAME WALK EDIT TARGET that currently uses the WRONG camera/facing. Image3 isolates the ORIGINAL IDLE and is the authoritative camera/body reference.
Repair image2 into a coherent eight-frame walk that matches image3's original camera, face, shoulder arrangement and asymmetrical infection. Asset type: production 2D pixel-painted game walking sprite atlas, 4 columns by 2 rows, exactly eight complete individual frames in row-major order. Keep every sprite entirely inside its own equal cell with generous transparent edge margin, a common character scale and foot baseline, fixed camera and fixed light. Genuine transparent background with alpha; no drawn checker pattern, no white background, no ground shadows, no labels, text or grid borders. Preserve the supplied character's crisp dark outline, warm cloth/fur palette, glossy black parasite, cyan fissures and yellow infected eye. This must be eight different mechanically plausible consecutive walking poses, not repeated poses, not unrelated action poses.
CRITICAL VIEW LOCK: in every cell use image3's slightly elevated front-LEFT three-quarter view. Snout points screen-LEFT, normal fur arm is on viewer's LEFT, large BLACK cyan-cracked infected arm/shoulder is on viewer's RIGHT. Walk toward screen-LEFT. Do not use image2's right-pointing snout. Do not rotate toward the other side in later frames. Keep the same cream/charcoal face stripes, one yellow corrupted eye, battered brown shoulder armor, giant ivory claws and black tendrils.
Leg identities: healthy gray-fur leg/ivory toes remain gray; infected cyan-cracked BLACK leg/ivory toes remain black. Neither switches material, hip attachment or identity when moving past the other.
Eight-pose physical sequence moving LEFT:
1 top-left: HEALTHY GRAY FOOT contacts forward toward left; BLACK FOOT trails behind toward right.
2: gray foot loads flat ahead; black heel lifts behind.
3: gray foot planted under body; BLACK swinging foot passes close beneath hips.
4: gray foot supports from behind; BLACK knee/foot lifts toward the left in preparation.
5 bottom-left: BLACK FOOT contacts forward toward left, HEALTHY GRAY FOOT trails to right. This MUST use the opposite planted leg from frame1.
6: black foot loads flat in front; gray heel lifts behind.
7: black foot planted beneath torso; healthy GRAY foot passes close beneath hips.
8: black leg supports from behind; GRAY knee/foot lifts forward left, preparing frame1.
Maintain the heavy hunched badger stance and natural opposite arm swing without changing arm identity. Use small torso weight shift, no exaggerated running kick, no duplicated first half. Keep claws, tendrils and all toes INSIDE cells with ample margin. Return only the repaired eight-frame walk atlas.

