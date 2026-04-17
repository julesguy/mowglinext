import type {Map as MapType, MapArea} from "../../../types/ros.ts";
import {
    DockFeatureBase,
    MowingAreaFeature,
    MowingFeature,
    MowingFeatureBase,
    NavigationFeature,
    ObstacleFeature,
} from "../../../types/map.ts";
import {transpose} from "../../../utils/map.tsx";

export function buildAreaFeatures(
    areas: MapArea[],
    type: "area" | "navigation",
    offsetX: number,
    offsetY: number,
    datum: [number, number, number],
): Record<string, MowingFeatureBase> {
    return areas?.flatMap((area, index): MowingFeatureBase[] => {
        if (!area.area?.points?.length) {
            return [];
        }

        const nfeat = type == "area"
            ? new MowingAreaFeature(type + "-" + index.toString() + "-area-0", index + 1)
            : new NavigationFeature(type + "-" + index.toString() + "-area-0");
        nfeat.setArea(area, offsetX, offsetY, datum);

        let obstacles: ObstacleFeature[] = [];

        if ((nfeat instanceof MowingAreaFeature) && (area.obstacles))
            obstacles = area.obstacles.map((obstacle, oindex) => {
                const nobst = new ObstacleFeature(
                    type + "-" + index.toString() + "-obstacle-" + oindex.toString(),
                    nfeat,
                );
                if (obstacle.points)
                    nobst.transpose(obstacle.points, offsetX, offsetY, datum);
                return nobst;
            });
        return [nfeat, ...obstacles];
    }).reduce((acc, val): Record<string, MowingFeatureBase> => {
        if (val.id == undefined) {
            return acc;
        }
        acc[val.id] = val;
        return acc;
    }, {} as Record<string, MowingFeatureBase>);
}

export function buildMapFeatures(
    map: MapType,
    offsetX: number,
    offsetY: number,
    datum: [number, number, number],
): Record<string, MowingFeature> {
    const workingAreas = buildAreaFeatures(map.working_area ?? [], "area", offsetX, offsetY, datum);
    const navigationAreas = buildAreaFeatures(map.navigation_areas ?? [], "navigation", offsetX, offsetY, datum);
    const features: Record<string, MowingFeature> = {...workingAreas, ...navigationAreas};
    const dock_lonlat = transpose(offsetX, offsetY, datum, map.dock_y ?? 0, map.dock_x ?? 0);
    features["dock"] = new DockFeatureBase(dock_lonlat, map.dock_heading ?? 0);
    return features;
}
