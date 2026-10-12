# Floating Island

Diorama-byggare i Godot 4.7 (Forward+). Klart: etapp 0 (stil), 1 (mark), 2 (vatten), 3 (växter) 4 (ruiner) 5 (himmel och väder) och 6 (ljus, kamera, spara och export, effekter).

## Köra

Dubbelklicka `run.bat`.

| Gör | Hur |
|---|---|
| Använd verktyg | Vänster musknapp + dra |
| Omvänt (höj↔sänk, rita↔sudda land, vatten↔torka) | Håll Shift |
| Rotera | Höger musknapp + dra |
| Panorera | Mitten + dra |
| Zooma | Hjulet |
| Penselstorlek | `[` och `]`, eller reglaget |
| Ångra / gör om | Ctrl+Z / Ctrl+Y |

Fliken **Mark**: Höj, Sänk, Jämna, Platta · Rita land, Sudda land · **Undersida**: Sudda under (nöter bort öns undersida nedifrån, högst upp till det ljusa berget under jorden; Shift bygger på igen) och Sudda rötter (klipper bort de delar av rötterna som penseln drar över, och det som växer vidare därifrån; Shift med Rötter gör detsamma). Rötter, träd och buskar har reglagen **Mossa** (samma mossa som stenarna, delad i `shaders/noise.gdshaderinc`; på träd kryper mycket mossa fläckvis upp längs stammen till första förgreningen), **Struktur** och **Relief** · Rötter (rita där rötterna ska börja: på marken kryper de över gräs, stenlagt, stenblock, småsten, murar och pelare och tippar över kanten; på undersidan och klippan hänger de. Reglagen Storlek (skalar hela rotsystemet), Längd, Bredd, Tjocklek, Täthet, Grenar (högst så många per klyka), Mellanrum (minsta sträcka mellan klykor), Vinkel (som en ny gren lämnar sin rot i), Djup (hur många gånger en rot får dela sig), Slingring, Klättra (hur gärna de tar sig över murar, pelare och stenar i stället för runt), Tyngd, Bark och Färg gäller nästa rötter och ändrar också de senast ritade; Stiliserat återställer; Shift tar bort) · Vatten, Torka · måla Gräs, Plattor (lagd sten), Stenar (lösa stenar i olika storlekar), Sand, Mossa, Jord.

**Vatten** gräver en skål och fyller den. Nivån sätts där du börjar dra; dras penseln nedför följer nivån med ner, så det blir en bäck. Börjar du i en damm förlänger du den på samma nivå. Når vattnet kanten blir det vattenfall. **Torka** tar bort vattnet och fyller igen gropen.

Fliken **Växter**: Lövträd, Gran, Höstträd, Torrträd, Sagoträd · Buske, Blombuske, Ormbunke, Högt gräs · Blommor, Klöver, Svamp · Stenblock, Småsten, Trampstenar · Vass, Näckros · Ta bort.

Klicka för en, håll och dra för att strö ut fler (Styrka = hur tätt). Shift tar bort den valda sorten, Ta bort tar allt under penseln. Träd, buskar och stenar märker marken runt sig och trycker undan gräset. Vass växer i strandkanten, näckrosor flyter på dammar. Koi dyker upp av sig själva i dammar som är stora och djupa nog.

**Träd genereras** (`scripts/tree_builder.gd`) efter Weber & Penns parametriska modell (samma som Blenders Sapling): stam, huvudgrenar runt stammen i gyllene vinkeln, grenarnas längd efter kronformen och förgrening i flera led; lövkronan är klungor av lövkort, granen får barrsjok längs grenarna. Reglage per trädsort: Höjd, Variation, Stam, Krokighet, Grenar, Förgrening, Grenlängd, Grenvinkel, Kronform (spetsig, rund, paraply), Stambas, Lövmängd, Lövstorlek, Löv- och Barkfärg. Stenar under träd får mer mossa.

**Samspel**: träd och buskar känner av stenar, murar och pelare (samma höjdraster som rötterna) och böjer sig runt dem i stället för att växa igenom; läggs en sten eller mur nära ett träd efteråt byggs trädet om. Klickar man ut ett träd ovanpå ett av samma sort smälter de ihop: stammarna växer från en gemensam fot, lutar isär och kronorna flyter ihop. Spöket för ett träd visar samma böjning som trädet får. Stenar tar bort gräset bara precis intill sig.

**Placera tätt och vrid**: ett klick får ställa saker ända intill varandra; bara det den faktiskt skulle stå på räknas som i vägen. Det du klickar ut vrids efter kameran, så det står vänt likadant mot dig hur du än vridit vyn; Q och E vrider det 15° i taget, och spöket visar vridningen. Penseln sprider saker med deras vanliga avstånd och slumpad vridning.

**Stenar under ön**: med en stensort vald kan man klicka eller måla stenar på klippkanten och öns undersida också. De sätter sig med den platta sidan mot berget, sjunker in en bit och buktar ut åt sidan eller nedåt; spöket visar det, och Shift tar bort dem där. **Berg** (under Stenar i fliken Växter): stora stenar av samma slag som stenblocken, med samma reglage, som penseln lägger tätt och sänker djupt så att ett drag blir en sammanvuxen häll. Höjer man marken under följer stenarna med utan att dras ut. Målar man berg över berg som redan ligger lägger sig de nya blocken ovanpå, högst mitt i berget och gradvis nedsjunkna i lagret under ju närmare bergets kant de ligger, så berget växer som en kulle. Bergets former byggs i bakgrunden när programmet startar, och rötterna läser stenarnas grova skal i stället för hela den detaljerade ytan, så målandet inte hackar.

**Måla över**: att klicka ut något där det redan står något tar bort det som står i vägen (spöket blir rött innan). Penseln målar över saker av samma storleksklass men aldrig över större saker, så småsten runt ett stenblock lämnar blocket kvar. Spöket är grått där saken inte får stå alls. **Död ved och ved** (`scripts/wood_builder.gd`, `shaders/wood.gdshader`) är stiliserat trä: barkplattor med djupa fåror, upphöjd barkkant runt snittytor med spiralringar, rötter som breder ut sig, knaggar och splittrade ändar.

**Fliken Prylar** (`scripts/item_builder.gd`, `shaders/item.gdshader`, `shaders/flame.gdshader`): Eldstad, Fackla, Stearinljus och Lykta lyser med fladdrande ljus; Tält, Ryggsäck, Koffert, Gryta (hänger på en trefot över en eldstad om du sätter den där), Picknickfilt (följer sluttningen); Huggkubbe med yxa och kluven ved, Yxa, Vedtrave (kluven ved under tak), Rund vedtrave (stockar i triangel), Spade, Hacka; Flaskor, Böcker, Korg, Tunna, Skylt. Små saker ställer sig ovanpå murar och stenar. Allt är målat i samma handgjorda stil som stubben: avfasade kanter som slits ljusa, och varje material målas på sitt sätt (metall, tyg, läder, glas, flätat, papper, vax). Allt trä, som plankor, tunnstavar, stolpar, skaft och eldstadens ved, byggs av samma träbyggare som stubben, och eldstadens stenar är genererade stenar. **Verktygen** (Spade, Hacka, Yxa) faller åt det håll de pekar, bort från dig och vridna med Q och E, tills de ligger på marken eller lutar mot det första som står i vägen: en stubbe, en tunna, en kista, en mur eller ett träd. Spöket visar hur de kommer att ligga, och flyttas det som de lutar mot lägger de sig om. Varje sak har Storlek, Variation och färger, ljusen även Ljusstyrka. Under Växter finns **Död ved**: en multnande Stock och en gammal Stubbe (Tjocklek, Mossa, Svampar).

**Granen** är stiliserad efter Quaternius-granarna: hängande, fransiga våningar runt stammen (reglage Våningar, Bredd, Hängning, Kronform, Stambas, Fransighet, Krokighet). **Stenar kan staplas**: klicka en sten på en annan (eller på en mur) så sjunker den halvvägs ner i den och de blir en klippa. **Spöke**: när du placerar visar ett halvgenomskinligt spöke exakt vad ett klick lägger dit, grönt där det får plats och rött där det inte får. Stenarnas yta har relief (bump mapping i shadern) och glesa sprickor.

**Frukt**: lövträden har reglagen Frukt och Fruktstorlek och en fruktfärg (äpplen, bär). **Småväxter genereras** (`scripts/plant_gen.gd`, `shaders/plant.gdshader`): ormbunke (Blad, Böjning, Bredd), blommor (Stjälkar, Kronblad, Blomstorlek, Kupning; färg på blad, kronblad och mitt), klöver (Täthet, Blommor), svamp (Antal, Hattbredd, Hattform, Prickar; färg på hatt, fot och prickar) och högt gräs (Strån, Böjning, Bredd, Spridning, Vippor, Gräsfärg). Buskar och blombuskar byggs som låga träd med blommor eller bär. Bara vass och näckros har ännu inga reglage.

**Stenar genereras** (`scripts/rock_builder.gd`): en sten är det som blir kvar när 15–30 slumpade plan skär bort bitar av en boll (idén bakom Rock Forge). Snitten görs på riktigt, så kanterna blir skarpa, men ytorna buktar ojämnt med gropar och knölar. Skuggaren målar en bruten ljus linje längs kanterna, sprickor som smalnar av och tar slut, med ljusa kanter, och små gropar. Med Kantighet på noll slätas formen ut helt, så det inte finns några kanter kvar. Mossan är ett ludd av tätt packade skott (Voronoi-celler, eftersom varje skott tar marken runt sig från grannarna) i tre storlekar som var och en tonas in först när den är större än en pixel, så det finns ludd i den skala man tittar, över mjuka svällningar. Fläckarna slutar smuligt, och mossan ligger över stenens relief, fyller sprickorna och tunnas ut över kanterna. **Relief** låter sprickor och gropar fånga ljuset som en normal map (räknad i skuggaren), djupare ju högre ratten står. Ytorna får var sin gråton, och mossan lägger sig på topparna men inte på kanterna. Kantigare stenar får färre och större ytor. Varje stensort har reglage som visas när den är vald: Storlek, Variation, Kantighet, Platthet, Avlånghet, Mossa, Textur (sprickor, gropar och kantlinjer), Relief och Färg. De gäller nästa stenar och ändrar också det senast målade. Stenar nära vatten och under träd får mer mossa. Penseln har **Täthet** och **Klungor** när man målar ut saker; med Klungor uppe samlas småsten kring stenblockens fot.

Modellerna kommer från Quaternius Stylized Nature MegaKit (CC0, `assets/quaternius`), laddas som glTF när programmet startar och får våra egna shaders.

Fliken **Ruiner**: Mur (dra längs marken), Pelare (klicka), Valv (dra från fot till fot; dras det längs en mur blir det en öppning i muren, med fullhöga pelare), Trappa (dra från nedersta steget; byggd i murstenar och klättrar till Höjd, så den möter en övervåning med samma Höjd), Golv (stengolv på marken, eller mer av en våning du börjar på), Övervåning (måla; våningen hamnar Höjd över marken, eller över våningen du börjar på, står på murar ner till marken och får bröstvärn; pelare under den växer upp och bär den), Dörr och Fönster (klicka på en mur, eller dra längs den för fler; rundbåge av kilstenar överst; fönstrets underkant hamnar på Höjd så långt muren räcker), Riv (murar och golv kapas bara under penseln). Höjd (0,5–5 m) gäller murar, pelare, valv, trappor, övervåningar och fönster; ett valv i en mur behåller sin egen höjd. Reglagen visar sina värden. Börjar eller slutar du nära en annan bit hakar den i. **Höjd** gäller det du bygger härnäst; **Ålder** gäller allt: mossan följer reglaget direkt, stenarna rasar när du släpper. Ruinerna byggs sten för sten i `scripts/ruin_builder.gd`, så de följer marken när du formar om den.

Fliken **Väder**: Tid (dygnet runt), Måne (faser), Moln · Dimma, Regn, Snö · Vind (löv blåser från träden och allt svajar mer), Eldflugor (kommer fram i skymningen) · Låt tiden gå (ett dygn på fyra minuter, månen går runt på åtta dygn). Regn gör alla ytor blöta och glansiga, ringar sprids på vattnet och droppar stänker upp ur gräs, sten och murkrön; snö lägger sig på allt som vetter mot himlen. Himlens stjärnor och stjärnfall bygger på tekniken i GDQuests Stylized Sky (MIT).

Fliken **Ljus**: färgton för himmel, horisont, under, moln, sol och dimma (vit = dygnets egen färg) · Sol, Omgivning, Exponering · Återställ ljuset.

Fliken **Kamera**: Lins (Brännvidd, Fokus, Bländare) · Bild (Zoom, Vinkel, Höjd; följer musen) · **Rotation**: Fart (°/s), Variation, Tid, Medsols/Motsols · **Höjdvåg**: Styrka (m upp och ner), Tid. Båda vågorna formas för hand genom att dra punkterna i kurvan; Sinus återställer. Kameran kretsar runt öns mitt och står längre bort ju större ön är; moln och skärpedjup följer med.

Fliken **Effekter**:
- **Glöd**: Styrka, Bloom, Tröskel.
- **Ljusstrålar**: Strålar och Längd (solstrålar när solen syns i eller strax utanför bild), Volymljus och Ljus i dis (ett dis runt ön som solen lyser upp, så ljuset faller i skaft mellan träd och murar).
- **Färg**: Kontrast, Ljushet, Mättnad, Temperatur, Färgton, och en färg för Skuggor och en för Högdagrar.
- **Lins och film**: Vinjett, Filmkorn, Färgfransar, Skärpa, Hörnskugga.
- Återställ effekterna.

Effekterna sparas i ön och följer med i bild, film och bakgrund.

Fliken **Export**: upplösning, längd · **Bild** (PNG utan panel), **Film** och **Bakgrund** (AVI). Bakgrunden blir ett helt varv runt ön med hela vågor, så den loopar sömlöst. Allt hamnar i `Bilder\Floating Island`. Filmer spelas in i ett eget fönster med Godots Movie Maker, ungefär fem gånger långsammare än realtid.

**Levande bakgrund:** installera gratisprogrammet Lively Wallpaper (Microsoft Store eller github.com/rocksdanister/lively), välj Lägg till bakgrund och peka på Bakgrund-filen.

**Panelen** sitter längs vänstra kanten. Knappen ‹ uppe i panelen (eller Tab) fäller in den till en liten flik, **Verktyg ›**, och ön glider in mot mitten av skärmen. **Spara / Öppna** (överst i panelen, Ctrl+S / Ctrl+O) sparar ön som `.island` i `Dokument\Floating Island`, med mark, växter, ruiner, väder, ljus, kamera och effekter.

## snapshot (för att jämföra utseende)

```sh
./snap.sh namn --yaw=40 --pitch=32 --dist=56 --sun=36 --sun_yaw=125 [--test=sculpt|undo|hover|water|dry|stones|plants|trees|remove|paint|ruins|ruins_new|ruins_old|ruins_cut|storey|storey2|openings|holes|age_undo|weather|light|camera|files|export|bigisland|loopmath|ff_live|post] [--tab=n] [--fold] [--rays= --volume= --temperature= --vignette= ...] [--age=0..1] [--target=x,y,z] [--hour= --moon_phase= --clouds= --fog= --rain= --snow= --wind= --fireflies=] [--noui]
```

Renderar en bild till `shots/namn.png` och skriver ut fps. `--test` kör ett inspelat pass genom riktiga musklick och drag (se `scripts/test_driver.gd`).

## Hur det hänger ihop

- `scripts/island_data.gd` – ön som fält på ett rutnät (32 m, 161 punkter): avstånd till kusten (sdf), höjd, markmaterial (splat) och var något redan står. Alla penseloperationer finns här och markerar vad som ändrats.
- `scripts/island_mesher.gd` – en ruta (16×16 celler) i taget: marching squares över sdf ger kustlinjen; ovansidan och kroppen (jord/sten-kjol och hängande undersida) byggs var för sig.
- `scripts/island_view.gd` – rutorna i scenen. Bygger bara om det som ändrats, med en tidsbudget per bildruta. Ovansidan byggs om vid all redigering, kroppen bara när kusten flyttas.
- Gräset byggs aldrig om: varje tuva läser en terrängtextur (höjd, kustavstånd, upptaget, gräsandel) i shadern och bestämmer själv om och hur högt den växer.
- `shaders/noise.gdshaderinc` – brus i världskoordinater som alla material delar, så mossa och torra fläckar fortsätter över skarvarna. Markmaterialen budar med målad vikt plus egen höjd; kullerstenarna budar med sina kupoler, så en stenyta fransar ut i lösa stenar mot gräset.
- `scripts/water_mesher.gd` – vattenytan per ruta (marching squares över vattenmasken, klippt vid kusten) och vattenfallen som hänger där vattnet når kusten. Ytan dras lite bredare än det målade vattnet, så strandlinjen blir där ytan skär slänten.
- `shaders/water.gdshader` – ser genom ytan via skärmtexturen, färgar efter hur mycket vatten blicken går genom, skum där slänten möter ytan, krusningar som rinner nedför i bäckar.
- `scripts/prop_catalog.gd` – alla sorter: höjd, avstånd, var de får stå, hur de märker marken; laddar kit-modeller och byter material.
- `scripts/prop_layer.gd` – det som står på ön, som små poster (sort, plats, vridning, storlek); noderna byggs från posterna, så ångra och sparning bara behöver posterna.
- `scripts/plant_builder.gd`, `scripts/fish_school.gd` – vass, näckrosor och koi, byggda i kod.
- `scripts/brush.gd` – musstrålen marscheras genom höjdfältet (ingen fysik). Varje drag är ett ångra-steg.
- `scripts/root_builder.gd`, `scripts/root_layer.gd`, `shaders/roots.gdshader` – rötter. Space colonization (Runions m.fl. 2007) upp och ner: ett moln av attraktionspunkter hänger under varje startpunkt och rötterna växer mot det; tjockleken följer rörmodellen. Barken är Quaternius Bark_TwistedTree (CC0). Förhandsvisningen växer i en arbetstråd.
- `scripts/post.gd`, `shaders/post.gdshader`, `shaders/shafts.gdshader` – effekterna. Glöd, volymljus och hörnskugga är Godots egna. Solstrålarna är en radiell oskärpa mot solen (Mitchell, GPU Gems 3 kap. 13, samma idé som CC0-shadern "Screen Space God Rays" på godotshaders.com), där djupbufferten avgör vad som är öppen himmel. Färg, vinjett, korn och fransar är ett skärmpass under panelen.
