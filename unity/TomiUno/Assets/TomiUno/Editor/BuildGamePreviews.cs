using System;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEditor.Build.Reporting;
using UnityEngine;
using Tomi.Uno;

// Export only this preview scene. Does not build or modify the Flutter app.
public static class BuildGamePreviews
{
    const string ScenePath="Assets/Scenes/TomiAllGamesPreview.unity";
    [MenuItem("TOMI/Open all-games preview")]
    public static void Open()
    {
        if(!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())return;
        EnsureScene();
        EditorSceneManager.OpenScene(ScenePath);
    }
    static void EnsureScene()
    {
        if(File.Exists(ScenePath))return;
        var scene=EditorSceneManager.NewScene(NewSceneSetup.EmptyScene,NewSceneMode.Single);
        new GameObject("TOMI five-game preview").AddComponent<AllGamesPreview>();
        Directory.CreateDirectory("Assets/Scenes");AssetDatabase.Refresh();
        EditorSceneManager.SaveScene(scene,ScenePath);
    }
    static void EnsureSurface()
    {
        const string path="Assets/TomiUno/Resources/TomiPreviewSurface.mat";
        if(AssetDatabase.LoadAssetAtPath<Material>(path)!=null)return;
        var shader=Shader.Find("Standard");
        if(shader==null)throw new InvalidOperationException("This project requires the built-in rendering pipeline and Standard shader.");
        Directory.CreateDirectory("Assets/TomiUno/Resources");AssetDatabase.Refresh();
        AssetDatabase.CreateAsset(new Material(shader),path);
        AssetDatabase.SaveAssets();
    }
    [MenuItem("TOMI/Build all-games WebGL preview")]
    public static void WebGL()
    {
        if(!BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.WebGL,BuildTarget.WebGL))
            throw new InvalidOperationException("Install WebGL Build Support for Unity 6000.0.62f1 in Unity Hub.");
        if(!Application.isBatchMode&&!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())return;
        EnsureScene();EnsureSurface();
        var previous=PlayerSettings.WebGL.compressionFormat;
        try
        {
            // The output can be served by a regular HTTP server without gzip/brotli header setup.
            PlayerSettings.WebGL.compressionFormat=WebGLCompressionFormat.Disabled;
            var report=BuildPipeline.BuildPlayer(new[]{ScenePath},"Builds/WebGL",BuildTarget.WebGL,BuildOptions.None);
            if(report.summary.result!=BuildResult.Succeeded)
                throw new InvalidOperationException("Unity preview export failed; inspect the Editor build log.");
            Debug.Log("TOMI Unity preview exported to Builds/WebGL. Serve this directory over HTTP.");
        }
        finally {PlayerSettings.WebGL.compressionFormat=previous;}
    }
}
