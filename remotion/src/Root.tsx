import { Composition } from "remotion";
import { Antios10PaletteOnlyPreview, Antios10Preview } from "./Composition";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Antios10Preview"
        component={Antios10Preview}
        durationInFrames={720}
        fps={30}
        width={1080}
        height={1920}
      />
      <Composition
        id="Antios10PreviewPaletteOnly"
        component={Antios10PaletteOnlyPreview}
        durationInFrames={450}
        fps={30}
        width={1080}
        height={1920}
      />
    </>
  );
};
