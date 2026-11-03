using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using Tomi.Uno;

public static class CreatePreviewScene
{
    [MenuItem("TOMI/Create UNO preview scene")]
    public static void Create()
    {
        if (!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo()) return;
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        new GameObject("TOMI UNO • design sandbox").AddComponent<UnoTablePreview>();
        System.IO.Directory.CreateDirectory("Assets/Scenes");
        EditorSceneManager.SaveScene(scene, "Assets/Scenes/TomiUnoPreview.unity");
        EditorBuildSettings.scenes = new[] {new EditorBuildSettingsScene(scene.path, true)};
        Selection.activeGameObject = Object.FindFirstObjectByType<UnoTablePreview>().gameObject;
    }
}
